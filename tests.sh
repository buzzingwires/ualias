#!/bin/sh -u

OUTPUT=
STATUS=
TESTNO=0

TEST_FILES="./tests"
TEST_SCRIPTS="$TEST_FILES/scripts"
TEST_LINKS="$TEST_FILES/links"

UACMD="./ualias --link-dir \"$TEST_LINKS\" --scripts-dir \"$TEST_SCRIPTS\" "

reset_directories()
{
	chmod 700 "$TEST_SCRIPTS"
	chmod 700 "$TEST_LINKS"
	rm -r "$TEST_FILES"
	mkdir -m 700 -p "$TEST_SCRIPTS"
	mkdir -m 700 -p "$TEST_LINKS"
}

#Arg 1: Section description
tell_section()
{
	TESTNO=0
	echo "$1"
}

increment_testno()
{
	TESTNO=$((TESTNO + 1))
}

#Arg 1: Command
#Arg 2: Expected value
#Arg 3: Received value
tell_failure()
{
		echo "INCORRECT TEST NUMBER $TESTNO OUTPUT for $1"
		echo "EXPECTED:"
		echo "$2"
		echo "RECEIVED:"
		echo "$OUTPUT"
}

#Arg 1: Command
assert_fail_status()
{
	increment_testno
	if sh -e -f -u -c "$1" > /dev/null 2>&1
	then
		tell_failure "$1" "NONZERO EXIT STATUS" "$OUTPUT"
	fi
}

#Arg 1: Command
run_asserting_success()
{
	OUTPUT="$(sh -e -f -u -c "$1" 2>&1)"
	STATUS="$?"
	if [ $STATUS -ne 0 ]
	then
		tell_failure "$1" "ZERO EXIT STATUS" "$OUTPUT"
	fi
}

#Arg 1: Command
#Arg 2: Pattern
assert_output()
{
	increment_testno
	run_asserting_success "$1"
	if ! echo "$OUTPUT" | grep -qF "$2"
	then
		tell_failure "$1" "$2" "$OUTPUT"
	fi
}

#Arg 1: Command
#Arg 2: Expected output
assert_exact_output()
{
	increment_testno
	run_asserting_success "$1"
	if ! [ "$OUTPUT" = "$2" ]
	then
		tell_failure "$1" "$2" "$OUTPUT"
	fi
}

#Arg 1: Command
assert_no_output()
{
	increment_testno
	run_asserting_success "$1"
	if [ -n "$OUTPUT" ]
	then
		tell_failure "$1" "NO OUTPUT" "$OUTPUT"
	fi
}

reset_directories

UANORMALOUTPUT="complicatedalias=\"echo \\\"\\\$\\\"\\\`\"
deletealias=\"echo deletealias recreated\"
equalalias=\"echo equalalias\"
postinstalias=\"echo Unecessary use of cat \"\$@\" | cat\"
spacealias=\"echo Overwriting spacealias\"
verbosealias=\"echo making verbose alias\""

UASHELLOUTPUT_BASE="$(realpath ./ualias) --verbose --overwrite --scripts-dir \"$(realpath "$TEST_SCRIPTS")\" --link-dir \"$(realpath "$TEST_LINKS")\""
UASHELLOUTPUT="#!/bin/sh -efu

$UASHELLOUTPUT_BASE \"complicatedalias\" \"echo \\\\\\\"\\\\\\\$\\\\\\\"\\\\\\\`\"
$UASHELLOUTPUT_BASE \"deletealias\" \"echo deletealias recreated\"
$UASHELLOUTPUT_BASE \"equalalias\" \"echo equalalias\"
$UASHELLOUTPUT_BASE \"postinstalias\" \"echo Unecessary use of cat\" --post-instruction \"| cat\"
$UASHELLOUTPUT_BASE \"spacealias\" \"echo Overwriting spacealias\"
$UASHELLOUTPUT_BASE \"verbosealias\" \"echo making verbose alias\""
#      result = getShellEscaped(ctx.exeName) &
#               " --verbose --overwrite --scripts-dir \"" &
#               getShellEscaped(ctx.storeDir) &
#               "\" --link-dir \"" &
#               getShellEscaped(ctx.linkDir) &
#               "\" \"" &
#               getShellEscaped(aliasName) &
#               "\" \"" &
#               getShellEscaped(aliasContents) &
#               "\""

UANAMEOUTPUT="complicatedalias deletealias equalalias postinstalias spacealias verbosealias "

tell_section "Try to include a positional argument with -d passed."
assert_fail_status "$UACMD -d option positional"

tell_section "Try getting help."
assert_output "$UACMD -h" "Manage shell-script based aliases"

tell_section "Try the two alias formats."
assert_no_output "$UACMD 'equalalias=echo equalalias'"
assert_no_output "$UACMD 'spacealias' 'echo spacealias'"

tell_section "Try overwriting an alias, first with and without the overwrite option."
assert_fail_status "$UACMD 'spacealias' 'echo Reassigning alias'"
assert_no_output "$UACMD -o 'spacealias' 'echo Overwriting spacealias'"

tell_section "Test verbose output"
assert_output "$UACMD -v 'verbosealias' 'echo making verbose alias'" "verbosealias=\"echo making verbose alias \"\$@\""

tell_section "Test the post instruction flag"
assert_output "$UACMD -v 'postinstalias' 'echo Unecessary use of cat' -p '| cat'" "postinstalias=\"echo Unecessary use of cat \"\$@\" | cat"

tell_section "Test shell special characters in an alias."
assert_output "$UACMD -v 'complicatedalias' 'echo \\\"\\\$\\\"\\\`'" "complicatedalias=\"echo \\\"\\\$\\\"\\\` \"\$@\""

tell_section "Try to make aliases when either directory is unavailable."
chmod 000 "$TEST_SCRIPTS"
assert_fail_status "$UACMD 'failalias' 'echo Failed alias because of scripts'"
chmod 000 "$TEST_LINKS"
assert_fail_status "$UACMD 'failalias' 'echo Failed alias because of links'"


tell_section "Test creating and deleting an alias"
chmod 755 "$TEST_SCRIPTS"
chmod 755 "$TEST_LINKS"
assert_no_output "$UACMD 'deletealias' 'echo deletealias'"
assert_no_output "$UACMD -d 'deletealias'"
assert_no_output "$UACMD 'deletealias' 'echo deletealias recreated'"

tell_section "Test trying to delete an alias when the symlink is mismatched"
assert_no_output "$UACMD 'falselinkalias' 'echo falselinkalias'"
ln -s -f "$TEST_SCRIPTS"/equalalias.sh "$TEST_LINKS"/falselinkalias
assert_fail_status "$UACMD -d 'falselinkalias'"

tell_section "Test trying to overwrite this. Ualias should not proceed if the link or script are tainted."
assert_fail_status "$UACMD 'falselinkalias' 'echo falselinkalias overwrite attempt 1'"
rm "$TEST_LINKS"/falselinkalias
assert_fail_status "$UACMD 'falselinkalias' 'echo falselinkalias overwrite attempt 2'"
assert_fail_status "$UACMD -d 'falselinkalias'"
assert_fail_status "$UACMD -o 'falselinkalias' 'echo falselinkalias overwrite attempt 3'"
rm "$TEST_SCRIPTS"/falselinkalias.sh
assert_no_output "$UACMD 'falselinkalias' 'echo falselinkalias  overwrite attempt 4'"

tell_section "The scripts and links must be exactly the right permissions, as well."
chmod 600 "$TEST_SCRIPTS"/falselinkalias.sh
assert_fail_status "$UACMD -d 'falselinkalias'"
chmod 755 "$TEST_SCRIPTS"/falselinkalias.sh
chmod 600 "$TEST_LINKS"/falselinkalias
assert_fail_status "$UACMD -d 'falselinkalias'"
chmod 755 "$TEST_LINKS"/falselinkalias
assert_no_output "$UACMD -d 'falselinkalias'"

tell_section "Test output of ualias"
assert_exact_output "$UACMD" "$UANORMALOUTPUT"
assert_exact_output "$UACMD -P shell" "$UASHELLOUTPUT"
ACTUALSHELLOUTPUT="$OUTPUT"
assert_exact_output "$UACMD -P name" "$UANAMEOUTPUT"

tell_section "Make sure the script will accurately recreate the original aliases."
reset_directories
sh -efu -c "$ACTUALSHELLOUTPUT" > /dev/null 2>&1
assert_exact_output "$UACMD -P shell" "$ACTUALSHELLOUTPUT"

tell_section "Taint script files. Not having the # DATE:  field is allowed, but everything else must match"
sed --in-place --posix --sandbox -e '/^# DATE: .*$/d' "$TEST_SCRIPTS/equalalias.sh"
assert_exact_output "$UACMD" "$UANORMALOUTPUT"
sed --in-place --posix --sandbox -e '/^# VERSION: .*$/d' "$TEST_SCRIPTS/equalalias.sh"
assert_output "$UACMD" "equalalias.sh' is not recognized as a ualias script."
