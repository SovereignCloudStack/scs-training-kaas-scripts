#!/bin/bash
#
# YAML parser helper
# We do some (incomplete) YAML parsing in bash as helper to 04-cloud-secret.sh
# to extract and construct a conforming clouds.yaml with exactly one
# openstack entry.
# This used to be SLOW by using several grep calls (forks) per line.
# Optimized a bit using three helpers; still going line by line in bash, so expect
# 2s for 1000 lines of clouds.yaml or so.
# 
# (c) Kurt Garloff <s7n@garloff.de>, 5/2025
# SPDX-License-Identifier: CC-BY-SA-4.0

# linestart detection
# $1: linestart to look for
# $2: string to search in
startswith()
{
	case "$2" in
		"$1"*)
			return 0;;
	esac
	return 1
}

# emptyline helper
# $1: line
islineempty()
{
	local LN
	IFS="	 " read LN < <(echo "$1")
	if test -z "$LN"; then return 0; fi
	if test "${LN:0:3}" = "---"; then return 0; else return 1; fi
}

# comment helper
# $1: line
islinecomment()
{
	local LN
	IFS="	 " read LN < <(echo "$1")
	if test "${LN:0:1}" = "#"; then return 0; else return 1; fi
}

# debug helper
# $1: Needed level
# $2: to output
yaml_debug()
{
	neededlvl=$1
	shift
	if test -n "$_yaml_debuglevel" && test $_yaml_debuglevel -ge $neededlvl; then
		echo "# DEBUG$neededlvl $@" 1>&2
	fi
}

###
# Assign extracted YAML to shell variables
# tag1.tag2.tag3-a: val123 becomes tag1__tag2__tag3_a=val123
# Arrays of plain values can be handled with shell arrays
# However: Arrays of dicts are common and we have to decide how to handle
# I.e. how to represent tag1=[{tag2:val2,tag3:val3},{tag2:val4,tag3:val5}]
# Approach: Store earch array element as parseable YAML
# tag1[0]="{tag2:val,tag3:val}", tag1[1]="{tag2:val4,tag3:val5}"
# For multiline arrays, basically do a multiline string handling

reset_vars()
{
	_prevstart=""
	_in_multiline=""
	_in_array=""
	unset _over
	_VARNM=""
	unset PREVASSIGN
	unset _in_arr
	unset _new_arr
	_MORE=""
}

reset_vars

# Set value
# $1 => line
fill_value()
{
	# global _VARNM _in_array _in_multiline
	local EXP NM VAL
	EXP=${1#$_prevstart}
	# Escape shell calling
	EXP="${EXP//\$/\\\$}"
	EXP="${EXP//\`/\\\`}"
	NM=${EXP%%:*}
	NM=${NM//-/_}
	# First element without leading __
	if test -n "$_VARNM"; then
		_VARNM="${_VARNM}__$NM"
	else
		_VARNM="$NM"
	fi
	_VARNM="${_VARNM//./_}"
	_VARNM="${_VARNM//\//__}"
	unset PREVASSIGN
	# Do we have a direct value
	if test "${EXP%%:*}" != "${EXP%:}"; then
		# FIXME: Don't do this on untrusted input
		VAL="${EXP#*:}"
		VAL="${VAL# }"
		# Dicts
		if test "${VAL:0:1}" = "{"; then
			 while IFS=": " read k p; do
				 yaml_debug 1 "dict $VPRE${_VARNM}__$k=\"$p\""
				 eval $VPRE${_VARNM}__$k=\"$p\"
			 done < <(echo "$VAL" | sed -e 's/{//' -e 's/}//' -e 's/,/\n/g')
		# Arrays
		elif test "${VAL:0:1}" = "["; then
			# FIXME: [ { , }, { , } ] won't be handled correctly
			# Ideas: sed 's/\({[^}]*}\)/\1/' extracts these, temporarily replace , with :: or so
			yaml_debug  "arr $VPRE${_VARNM}=($(echo "$VAL" | sed -e 's/\[/"/' -e 's/\]/"/' -e 's/, */" "/g'))"
			eval $VPRE$_VARNM="\"("$(echo "$VAL" | sed -e 's/\[/"/' -e 's/\]/"/' -e 's/, */" "/g')")\""
		# Multiline
		elif test "${VAL:0:1}" = "|"; then
			_in_multiline="#MARKER"
			yaml_debug 2 "Found multiline marker $VAL"
			#_prevstart="$_prevstart$_MORE"
		# None of the above
		else
			if test -n "$_in_multiline" -o -n "$_in_array"; then
				echo "#ERROR: multiline or array not expected $_VARNM" 1>&2
				exit 1
			else
				yaml_debug 1 "assign $VPRE$_VARNM=\"$VAL\""
				eval $VPRE$_VARNM=\"$VAL\"
				PREVASSIGN="$VAL"
			fi
		fi
	fi
}

# Fill in multiline and arrays into old variable
finalize_var()
{
	if test -z "$YAMLASSIGN" -o -z "$_VARNM"; then return; fi
	_VARNM="${_VARNM//./_}"
	_VARNM="${_VARNM//\//__}"
	yaml_debug 4 "finalize_var $_VARNM"
	if test -n "$_in_multiline"; then
		yaml_debug 1 "multiline $VPRE$_VARNM=\"$_in_multiline\""
		eval $VPRE$_VARNM="\"${_in_multiline}\""
		_in_multiline=""
	elif test -n "$_in_array"; then
		yaml_debug 1 "array $VPRE$_VARNM=($_in_array\")"
		eval $VPRE$_VARNM="($_in_array\")"
		_in_array=""
		if test -n "$_over"; then
			unset _over
			_prevstart="${_prevstart%$_MORE}"
		fi
	fi
	if test "${_VARNM%__*}" = "$_VARNM"; then
		_VARNM=""
	else
		_VARNM="${_VARNM%__*}"
	fi
}

# Helper: assign values
# "$1": The input line
parse_line()
{
	if test -z "$YAMLASSIGN"; then return; fi
	if islinecomment "$1" ; then return; fi
	#global _VARNM _prevstart
	yaml_debug 4 "parse_line \"$1\" $_VARNM \"$_prevstart\" \"$_MORE\" \"$_in_mult\"$_MORE\" iline\" \"$_in_array\""
	# OK several cases
	# (a) We have more indentation than before: new level
	# (b) Same indentation as before: another data field
	# (c) Lower indentation: remove last level
	# Work on (c):
	while ! startswith "$_prevstart" "$1"; do
		#echo "# Strip \"$_MORE\" in $LNNO \"$1\"" 1>&2
		finalize_var
		#_VARNM="${_VARNM%__*}"
		# FIXME: This assumes the indentations are regular
		_prevstart="${_prevstart%$_MORE}"
	done
	# TODO: If we are in array parsing mode, we basically just need
	# to determine whether we have a the end, a new element, or continuation
	# of the content of an array element.
	# Case (a)
	if startswith "$_prevstart ${_MORE# }" "$1"; then
		VAL="${1#$_prevstart ${_MORE# }}"
		VAL="${VAL//\$/\\\$}"
		VAL="${VAL//\`/\\\`}"
		#yaml_debug 4 "More indentation"
		if test -n "$_in_multiline"; then
			if test "$_in_multiline" = "#MARKER"; then
				_in_multiline="$VAL"
			else
				_in_multiline="$_in_multiline
$VAL"
			fi
		else
			# If we are already in an array, then we continue saving the contents
			# $_prevstart- denotes next element, $_prevstart$_MORE is continuation
			if test -n "$_in_array"; then
				# FIXME
				yaml_debug 4 "Add elemnt $VAL to array $_VARNM"
				_in_array="$_in_array
$VAL"
			# Beginning of an array (with optional addtl indentation)
			elif startswith "- " "$VAL"; then
				_prevstart="$_prevstart$_MORE"
				#TODO: Parse dicts in array
				_in_array="\"${VAL#- }"	# Open \" is intentional
				yaml_debug 2 "Found overindented array start ${1#$_prevstart$_MORE- }"
				_over=1
			# detect line-wrapped continuation
			elif test -n "$PREVASSIGN"; then
				yaml_debug 3 "Unexpected line continuation found -> multiline"
				_in_multiline="$PREVASSIGN
$VAL"
				unset PREVASSIGN
			# A new dict field in the array
			else
				_prevstart="$_prevstart$_MORE"
				fill_value "$1"
			fi
		fi
	# Case (b)
	else
		VAL="${1#$_prevstart}"
		if ! startswith "- " "$VAL"; then
			finalize_var
			fill_value "$1"
		elif test -n "$_in_array"; then
			# Handle array continuation
			_in_array="$_in_array\" \"${VAL#- }"
			yaml_debug 2 "Next array element ${VAL#- }"
		else
			# Handle array start
			_in_array="\"${VAL#- }"	# Open \" is intentional
			yaml_debug 2 "Found array start ${VAL#- }"
		fi
	fi
	#unset PREVASSIGN
}

# Helper: Parse YAML (recursive)
#
# We take two parameters
# $1: The indentation whitespace
# $2: "1" => We want more indentation
# $3-: The keywords
#
# Environment to pass special functions
# $RMVTREE nonempty: Do not output yaml path leading to this section
#   If $RMVTREE is set to all: Also remove the last tag
# $REPLACEKEY nonempty: Replace last part of the search value by $REPLACEKEY
# $INSERT and $APPEND is text injected in the outputted block (at beginning and end resp.)
# $INJECTSUB and $INJECTSUBKWD: inject text $INJECTSUB after the subsection $INJECTSUBKWD has been found
# $REMOVE is a tag to filter out
# $RMVCOMMENT nonempty: Strip comments
# $YAMLASSIGN fills shell variables with the parsed yaml
# 	where a variable a-b.c.d_e.f will look like a_b__c__d_e__f
# 	If you set $VPRE, variable names will be prefixed with $VPRE
#
# Return value: 0 if we found (and output) a block, 1 otherwise
extract_yaml_rec()
{
	#echo "DEBUG: Called extract_yaml_rec $@" 1>&2
	yaml_debug 3 "extract_yaml_rec \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" [...]"
	local previndent="$1"
	local more="$2"
	#global LNNO _MORE
	shift 2
	if test -n "$1"; then NOTFOUND=1; fi
	while IFS="" read line; do
		let LNNO+=1
		# Ignore empty lines
		#if echo "$line" | grep -q '^\s*$'; then continue; fi
		if islineempty "$line"; then continue; fi
		# First line of new block: We need more indentation ...
		if test "$more" = "1"; then
			if ! echo "$line" | grep -q "^$previndent\\(\\s\\|\\-\\)"; then return; fi
			more=$(echo "$line" | sed "s/^$previndent\\(\\s\\s*\\|\\- *\\)\\S.*\$/\\1/")
			if test "${more:0:1}" = "-"; then _new_arr=arr; else unset _in_arr; fi
			if test -z "$_MORE" -a -z "$_new_arr"; then _MORE="$more"; fi
			yaml_debug 4 "New indent level (line $LNNO): \"$previndent$more\" ($_new_arr)"
		fi
		# Detect less indentation than wanted, return
		#if ! echo "$line" | grep -q "^$previndent$more"; then return; fi
		if ! startswith "$previndent$more" "$line"; then
			if test -z "$1" -a -n "$_in_arr"; then echo "]"; unset _in_arr; fi
			finalize_var
			yaml_debug 4 "end of block"
			return
		fi
		# Strip comments if requested
		#if test -n "$RMVCOMMENT" && echo "$line" | grep -q '^\s*#'; then continue; fi
		if test -n "$RMVCOMMENT" && islinecomment "$line"; then continue; fi
		# OK, we we have at least the indentation level needed
		# 3 cases:
		# (a) We are prior to finding the right block, continue searching
		# (b1) Found it, no more nesting needed, output till the end
		# (b2) Found it, recurse into next keyword
		# (c) We idenitfy the end by finding a different keyword
		#
		# Case b1: No more keywords to look for, we found the previous ones if we
		# got here, just output until the less indentation clause above indicates the end
		if test -z "$1"; then
			#echo "$previndent$more# $LNNO: Outputing block"
			#if test -z "$REMOVE" || ! echo "$line" | grep -q "^$previndent$more$REMOVE:"; then
			if test -z "$REMOVE" || ! startswith "$previndent$more$REMOVE:" "$line"; then
				if test -n "$_new_arr"; then
					unset _new_arr
					_in_arr=1
					if test "$RMVTREE=all"; then
						echo -n "[${line##*- }"
					else
						echo -n "${line%- *}  [${line##*- }"
					fi
				elif test -n "$_in_arr"; then
					echo -n ",${line##*- }"
				else
					echo "$line"
				fi
				parse_line "$line"
			fi
			if test -n "$INJECTSUB" -a -n "$INJECTSUBKWD" && startswith "$previndent$more$INJECTSUBKWD:" "$line"; then
				echo "$INJECTSUB"
				while IFS="" read ln; do
					parse_line "$ln"
				done < <(echo "$INJECTSUB")
				unset INJECTSUB
			fi
			continue
		fi
		# b2: Search for the keyword
		#if echo "$line" | grep -q "^$previndent$more$1:"; then
		if startswith "$previndent$more$1:" "$line"; then
			#echo "$previndent$more# $LNNO: Found keyword $1"
			yaml_debug 4 "Found $1"
			if test -n "$REPLACEKEY" -a -z "$2"; then
				line=$(echo "$line" | sed "s@$1:@$REPLACEKEY:@")
				set -- "$REPLACEKEY" "$2" "$3"
			fi
			# Output tree unless we suppress it
			if test -z "$RMVTREE"; then
				echo "$line"
				parse_line "$line"
			else
				# At the leaf, we may hold a value
				if test -z "$2"; then
					if test "$RMVTREE" != "all"; then
						echo "$line" | grep --color=never "^$previndent$more$1: [^[:space:]]"
					else
						echo "$line" | grep --color=never "^$previndent$more$1: [^[:space:]]" | sed "s@^$previndent$more$1: @@"
					fi
					parse_line "$line"
				fi
			fi
			shift
			# TODO: Reformat INSERT to match
			if test -z "$1"; then
				NOTFOUND=0
				if test -n "$INSERT"; then echo "$INSERT"; parse_line "$INSERT"; fi
			fi
			#yaml_debug 4 "Now output block"
			extract_yaml_rec "$previndent$more" "1" "$@"
			# TODO: Reformat APPEND to match
			if test -z "$1" -a -n "$APPEND"; then echo "$APPEND"; parse_line "$APPEND"; fi
			# A return here would allows for only one block of a kind
			return $NOTFOUND
			# Otherwise we would have needed to save "$@" adn restore it here
		fi
		# a: OK, just continue to search (without the return above, this is also c)
	done
	if test -z "$1" -a -n "$_in_arr"; then echo "]"; unset _in_arr; fi
	finalize_var
	return $NOTFOUND
}

# Helper: extract_yaml
# $1: The tag to search for and output (separated by dots)
extract_yaml()
{
	local _RET
	reset_vars
	SRCH=($(echo "$1" | sed 's/\./ /g'))
	LNNO=0
	if test -z "${SRCH[0]}"; then _MORE="  "; else _MORE=""; fi
	extract_yaml_rec "" "" "${SRCH[@]}"
	_RET=$?
	finalize_var
	return $_RET
}

### helper for users
# $1 => var name
is_array()
{
	local OUT="$(declare -p $1 2>/dev/null)"
	if test $? = 0 && startswith "declare -a" "$OUT"; then return 0; else return 1; fi
}

### helper for users
# $1 => variable/line
is_dict()
{
	if test "${1%:*}" != "$1"; then return 0; else return 1; fi
}
