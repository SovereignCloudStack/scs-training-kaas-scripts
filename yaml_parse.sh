#!/bin/bash
#
# YAML parser helper
# We do some (incomplete) YAML parsing in bash as helper to 04-cloud-secret.sh
# to extract and construct a conforming clouds.yaml with exactly one
# openstack entry.
# This is SLOW by walking a file line by line, using several grep calls per line,
# which is a fork.
# Could be optimized by doing the simple things in bash, but this is not urgent.
# 
# (c) Kurt Garloff <s7n@garloff.de>, 5/2025
# SPDX-License-Identifier: CC-BY-SA-4.0
#
# Helper: Parse YAML (recursive)
#
# We take two parameters
# $1: The indentation whitespace
# $2: "1" => We want more indentation
# $3-: The keywords
#
# Environment to pass special functions
# $RMVTREE nonempty: Do not output yaml path leading to this section
# $INSERT and $APPEND is text injected in the outputted block (at beginning and end resp.)
# $REMOVE is a tag to filter out
# $RMVCOMMTENT nonempty: Strip comments
#
# Return value: 0 if we found (and output) a block, 1 otherwise
extract_yaml_rec()
{
	#echo "DEBUG: Called extract_yaml_rec $@" 1>&2
	local previndent="$1"
	local more="$2"
	#global LNNO
	shift 2
	if test -n "$1"; then NOTFOUND=1; fi
	while IFS="" read line; do
		let LNNO+=1
		# Ignore empty lines
		if echo "$line" | grep '^\s*$' >/dev/null 2>&1; then continue; fi
		# First line of new block: We need more indentation ...
		if test "$more" = "1"; then
		       if ! echo "$line" | grep "^$previndent\s" >/dev/null 2>&1; then return; fi
		       more=$(echo "$line" | sed "s/^$previndent\\(\s*\\)[^\s].*\$/\\1/")
		       #echo "$previndent$more# $LNNO: New indent level"
		fi
		# Detect less indentation than wanted, return
		if ! echo "$line" | grep "^$previndent$more" >/dev/null 2>&1; then return; fi
		# Strip comments if requested
		if test -n "$RMVCOMMENT" && echo "$line" | grep '^\s*#' >/dev/null 2>&1; then continue; fi
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
			if test -z "$REMOVE" || ! echo "$line" | grep "^$previndent$more$REMOVE:" >/dev/null 2>&1; then
				echo "$line"
			fi
			continue
		fi
		# b2: Search for the keyword
		if echo "$line" | grep "^$previndent$more$1:" >/dev/null 2>&1; then
			#echo "$previndent$more# $LNNO: Found keyword $1"
			# Output tree unless we suppress it
			if test -z "$RMVTREE"; then
				echo "$line"
			else
				# At the leaf, we may hold a value
				if test -z "$2"; then
					echo "$line" | grep --color=never "^$previndent$more$1: [^\\s]" 2>/dev/null
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
	LNNO=0
	SRCH=($(echo "$1" | sed 's/\./ /g'))
	extract_yaml_rec "" "" "${SRCH[@]}"
}

