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

###
# Assign extracted YAML to shell variables
# tag1.tag2.tag3-a: val123 becomes tag1__tag2__tag3_a=val123
# Arrays of plain values can be handled with shell arrays
# However: Arrays of dicts are common and we have to decide how to handle
# I.e. how to represent tag1=[{tag2:val2,tag3:val3},{tag2:val4,tag3:val5}]
# Approach: Store earch array element as parseable YAML
# tag1[0]="{tag2:val,tag3:val}", tag1[1]="{tag2:val4,tag3:val5}"
# For multiline arrays, basically do a multiline string handling

_VARNM=""
_prevstart=""
_MORE=""
_in_multiline=""
_in_array=""

fill_value()
{
	# global _VARNM _in_array _in_multiline
	local EXP NM VAL
	EXP=${1#$_prevstart}
	NM=${EXP%%:*}
	NM=${NM//-/_}
	# First element without leading __
	if test -n "$_VARNM"; then
		_VARNM="${_VARNM}__$NM"
	else
		_VARNM="$NM"
	fi
	# Do we have a direct value
	if test "${EXP%%:*}" != "${EXP%:}"; then
		VAL="${EXP#*:}"
		VAL="${VAL# }"
		# FIXME: Don't do this on untrusted input
		# Dicts
		if test "${VAL:0:1}" = "{"; then
			 while IFS=": " read k p; do
				 eval ${_VARNM}__$k="$p"
				 echo "#DEBUG1: ${_VARNM}__$k=\"$p\"" 1>&2
			 done < <(echo "$VAL" | sed -e 's/{//' -e 's/}//' -e 's/,/\n/g')
		# Arrays
		elif test "${VAL:0:1}" = "["; then
			eval $_VARNM="("$(echo "$VAL" | sed -e 's/\[/"/' -e 's/\]/"/' -e 's/, */" "/g')")"
			echo "#DEBUG2: ${_VARNM}=($(echo "$VAL" | sed -e 's/\[/"/' -e 's/\]/"/' -e 's/, */" "/g'))" 1>&2
		# Multiline
		elif test "${VAL:0:1}" = "|"; then
			_in_multiline="#MARKER"
			echo "#DEBUG: Found multiline marker $VAL" 1>&2
			#_prevstart="$_prevstart$_MORE"
		# None of the above
		else
			# Append multiline string
			if test -n "$_in_multiline"; then
				echo "#ERROR1" 1>&2
				if test "$_in_multiline" = "#MARKER"; then
					_in_multiline="$VAL"
				else
					_in_multiline="$_in_multiline
$VAL"
				fi
			elif test -n "$_in_array"; then
				_in_array="$_in_array \"$VAL\""
				echo "#ERROR2" 1>&2
			else
				eval $_VARNM="$VAL"
				echo "#DEBUG3: $_VARNM=\"$VAL\"" 1>&2
			fi
		fi
	fi
}

# Fill in multiline and arrays into old variable
finalize_var()
{
	if test -z "$YAMLASSIGN"; then return; fi
	if test -n "$_in_multiline"; then
		echo "#DEBUG4: $_VARNM=\"$_in_multiline\"" 1>&2
		eval $_VARNM="\"$_in_multiline\""
		_in_multiline=""
	elif test -n "$_in_array"; then
		echo "#DEBUG5: $_VARNM=($_in_array)" 1>&2
		eval $_VARNM="("$_in_array")"
		_in_array=""
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
	if startswith "$_prevstart$_MORE" "$1"; then
		if test -n "$_in_multiline"; then
			VAL="${1#$_prevstart$_MORE}"
			if test "$_in_multiline" = "#MARKER"; then
				_in_multiline="$VAL"
			else
				_in_multiline="$_in_multiline
$VAL"
			fi
		else
			# only accept addtl indentation for first element
			if startswith "$_prevstart$_MORE-" "$1" && test -z "$_in_array"; then
				#TODO: Parse dicts in array
				_in_array="$_in_array \"${1#$_prevstart$_MORE- }\""
				echo "#DEBUG: Found array start ${1#$_prevstart$_MORE- }" 1>&2
			# A new dict field in the array
			elif test -n "$_in_array"; then
				_in_array="$_in_array \"${1#$_prevstart$_MORE}\""
				echo "#DEBUG: Found dict array elem ${1#$_prevstart$_MORE}" 1>&2
			else
				_prevstart="$_prevstart$_MORE"
				fill_value "$1"
			fi
		fi
	# Case (b)
	else
		# TODO: Handle array continuation
		if startswith "$_prevstart-" "$1"; then
			_in_array="$_in_array \"${1#$_prevstart- }\""
			echo "#DEBUG: Found array elem ${1#$_prevstart- }" 1>&2
		else
			finalize_var
			fill_value "$1"
		fi
	fi
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
# $REPLACEKEY nonempty: Replace last part of the search value by $REPLACEKEY
# $INSERT and $APPEND is text injected in the outputted block (at beginning and end resp.)
# $INJECTSUB and $INJECTSUBKWD: inject text $INJECTSUB after the subsection $INJECTSUBKWD has been found
# $REMOVE is a tag to filter out
# $RMVCOMMENT nonempty: Strip comments
# $YAMLASSIGN fills shell variables with the parsed yaml
# 	where a variable a-b.c.d_e.f will look like a_b__c__d_e__f
#
# Return value: 0 if we found (and output) a block, 1 otherwise
extract_yaml_rec()
{
	#echo "DEBUG: Called extract_yaml_rec $@" 1>&2
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
		       if ! echo "$line" | grep -q "^$previndent\s"; then return; fi
		       more=$(echo "$line" | sed "s/^$previndent\\(\s*\\)[^\s].*\$/\\1/")
		       if test -z "$_MORE"; then _MORE="$more"; fi
		       #echo "$previndent$more# $LNNO: New indent level"
		fi
		# Detect less indentation than wanted, return
		#if ! echo "$line" | grep -q "^$previndent$more"; then return; fi
		if ! startswith "$previndent$more" "$line"; then return; fi
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
				echo "$line"
				parse_line "$line"
			fi
			if test -n "$INJECTSUB" -a -n "$INJECTSUBKWD" && startswith "$previndent$more$INJECTSUBKWD:" "$line"; then
				echo "$INJECTSUB"
				parse_line "$INJECTSUB"
				unset INJECTSUB
			fi
			continue
		fi
		# b2: Search for the keyword
		#if echo "$line" | grep -q "^$previndent$more$1:"; then
		if startswith "$previndent$more$1:" "$line"; then
			#echo "$previndent$more# $LNNO: Found keyword $1"
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
					echo "$line" | grep --color=never "^$previndent$more$1: [^\\s]"
					parse_line "$line"
				fi
			fi
			shift
			# TODO: Reformat INSERT to match
			if test -z "$1"; then
				NOTFOUND=0
				if test -n "$INSERT"; then echo "$INSERT"; fi
			fi
			extract_yaml_rec "$previndent$more" "1" "$@"
			# TODO: Reformat APPEND to match
			if test -z "$1" -a -n "$APPEND"; then echo "$APPEND"; fi
			# A return here would allows for only one block of a kind
			return $NOTFOUND
			# Otherwise we would have needed to save "$@" adn restore it here
		fi
		# a: OK, just continue to search (without the return above, this is also c)
	done
	return $NOTFOUND
}

# Helper: extract_yaml
# $1: The tag to search for and output (separated by dots)
extract_yaml()
{
	local _RET
	_prevstart=""
	_in_multiline=""
	_in_array=""
	_VARNM=""
	SRCH=($(echo "$1" | sed 's/\./ /g'))
	LNNO=0
	if test -z "${SRCH[0]}"; then _MORE="  "; else _MORE=""; fi
	extract_yaml_rec "" "" "${SRCH[@]}"
	_RET=$?
	finalize_var
	return $_RET
}

