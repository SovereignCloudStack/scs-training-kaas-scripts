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
	if test -z "$LN"; then return 0; else return 1; fi
}

# comment helper
# $1: line
islinecomment()
{
	local LN
	IFS="	 " read LN < <(echo "$1")
	if test "${LN:0:1}" = "#"; then return 0; else return 1; fi
}

handle_array()
{
	# FIXME: Not yet implemented
	echo "Warning: handle_array is not yet implemented"
}


_VARNM=""
_prevstart=""
_MORE=""

fill_value()
{
	# global _VARNM
	local EXP NM
	EXP=${1#$_prevstart}
	NM=${EXP%%:*}
	NM=${NM//-/_}
	if test -n "$_VARNM"; then
		_VARNM="${_VARNM}__$NM"
	else
		_VARNM="$NM"
	fi
	if test "${EXP%%:*}" != "${EXP%:}"; then
		# TODO: Handle array
		# FIXME: Don't do this on untrusted input
		eval $_VARNM="${EXP#*: }"
		#echo "$_VARNM=\"${EXP#*: }\"" 1>&2
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
		_VARNM="${_VARNM%__*}"
		# FIXME: This assumes the indentations are regular
		_prevstart="${_prevstart%$_MORE}"
	done
	# Case (a)
	if startswith "$_prevstart$_MORE" "$1"; then
		_prevstart="$_prevstart$_MORE"
		if startswith "$_prevstart-" "$1"; then
			handle_array "$1"
		elif startswith "$_prevstart$_MORE-" "$1"; then
			_prevstart="$_prevstart$_MORE"
			handle_array "$1"
		else
			fill_value "$1"
		fi
	# Case (b)
	else
		# TODO: Handle array continuation
		_VARNM="${_VARNM%__*}"
		fill_value "$1"
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
# $ASSIGNYAML fills shell variables with the parsed yaml
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
				parse_line "$previndent$more" "$line"
			fi
			if test -n "$INJECTSUB" -a -n "$INJECTSUBKWD" && startswith "$previndent$more$INJECTSUBKWD:" "$line"; then
				echo "$INJECTSUB"
				parse_line "$previndent$more" "$INJECTSUB"
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
				parse_line "$previndent$more" "$line"
			else
				# At the leaf, we may hold a value
				if test -z "$2"; then
					echo "$line" | grep --color=never "^$previndent$more$1: [^\\s]"
					parse_line "$previndent$more" "$line"
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
	LNNO=0
	SRCH=($(echo "$1" | sed 's/\./ /g'))
	extract_yaml_rec "" "" "${SRCH[@]}"
	_RET=$?
	_prevstart=""
	return $_RET
}

