create or replace package tokenizer_test authid current_user is
/*
## Purpose ##

Unit tests for tokenizer.


## Example ##

begin
	tokenzier_test.run;
	tokenizer_test.run(tokenzier_test.c_dynamic_tests);
end;

*/
pragma serially_reusable;

--Globals to select which test suites to run.
c_test_whitespace              constant number := power(2, 1);
c_test_comment                 constant number := power(2, 2);
c_test_text                    constant number := power(2, 3);
c_test_numeric                 constant number := power(2, 4);
c_test_word                    constant number := power(2, 5);
c_test_inquiry_directive       constant number := power(2, 6);
c_test_preproc_control_token   constant number := power(2, 7);
c_test_3_character_punctuation constant number := power(2, 9);
c_test_2_character_punctuation constant number := power(2, 10);
c_test_1_character_punctuation constant number := power(2, 11);
c_test_unexpected              constant number := power(2, 12);
c_test_utf8                    constant number := power(2, 13);
c_test_other                   constant number := power(2, 14);

c_dynamic_tests             constant number := power(2, 30);

--Default option is to run all static test suites.
c_all_static_tests          constant number := c_test_whitespace+c_test_comment+
	c_test_text+c_test_numeric+c_test_word+c_test_inquiry_directive+
	c_test_preproc_control_token+c_test_3_character_punctuation+c_test_2_character_punctuation+
	c_test_1_character_punctuation+c_test_unexpected+c_test_utf8+c_test_other;

--Run the unit tests and display the results in dbms output.
procedure run(p_tests number default c_all_static_tests);

end;
/
create or replace package body tokenizer_test is
pragma serially_reusable;

--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;

--Global characters for testing.
g_4_byte_utf8 varchar2(1 char) := unistr('\d841\df79');  --The "cut" character in Cantonese.
g_2_byte_utf8 varchar2(1 char) := unistr('\00d0');       --The "eth" character, an upper case D with a line.

--Helper procedures.


--------------------------------------------------------------------------------
procedure assert_equals(p_test nvarchar2, p_expected nvarchar2, p_actual nvarchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with '||p_test);
		dbms_output.put_line('Expected: '||p_expected);
		dbms_output.put_line('Actual  : '||p_actual);
	end if;
end assert_equals;


--------------------------------------------------------------------------------
function get_value_n(p_source nclob, n number) return nvarchar2 is
	v_tokens token_table;
begin
	v_tokens := tokenizer.tokenize(p_source);
	return v_tokens(n).value;
end get_value_n;


--------------------------------------------------------------------------------
function get_sqlcode_n(p_source nclob, n number) return nvarchar2 is
	v_tokens token_table;
begin
	v_tokens := tokenizer.tokenize(p_source);
	return v_tokens(n).sqlcode;
end get_sqlcode_n;


--------------------------------------------------------------------------------
function get_sqlerrm_n(p_source nclob, n number) return nvarchar2 is
	v_tokens token_table;
begin
	v_tokens := tokenizer.tokenize(p_source);
	return v_tokens(n).sqlerrm;
end get_sqlerrm_n;


--------------------------------------------------------------------------------
--Simplifies calls to tokenize and print_tokens.
function lex(p_source nclob) return nclob is
begin
	return tokenizer.print_tokens(tokenizer.tokenize(p_source));
end lex;


--------------------------------------------------------------------------------
--Test Suites
procedure test_whitespace is
begin
	assert_equals('whitespace: 1a', 'whitespace EOF', lex(unistr('\3000')));
	assert_equals('whitespace: 1b', unistr('\3000'), get_value_n(unistr('\3000'), 1));
	assert_equals('whitespace: 2a', 'whitespace EOF', lex(chr(0)||chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||unistr('\3000')));
	--The chr(0) may prevent the string from being displayed properly.
	assert_equals('whitespace: 2b', chr(0)||chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||unistr('\3000'), get_value_n(chr(0)||chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||unistr('\3000'), 1));
	assert_equals('whitespace: 3', 'whitespace EOF', lex('	'));
	assert_equals('whitespace: 4', 'whitespace word whitespace word EOF', lex(' a a'));
end test_whitespace;


--------------------------------------------------------------------------------
procedure test_comment is
begin
	assert_equals('comment: 1a', 'whitespace comment EOF', lex('  --asdf'));
	assert_equals('comment: 1b', '--asdf', get_value_n('  --asdf', 2));
	assert_equals('comment: 2a', 'whitespace comment EOF', lex('  --asdf'||chr(13)||'asdf'));
	assert_equals('comment: 2b', '--asdf'||chr(13)||'asdf', get_value_n('  --asdf'||chr(13)||'asdf', 2));
	assert_equals('comment: 3', 'whitespace comment whitespace word EOF', lex('  --asdf'||chr(13)||chr(10)||'asdf'));
	assert_equals('comment: 4', 'whitespace comment whitespace word EOF', lex('  --asdf'||chr(10)||'asdf'));
	assert_equals('comment: 5', 'comment EOF', lex('--'));
	assert_equals('comment: 6', 'comment EOF', lex('/**/'));
	assert_equals('comment: 7', 'comment EOF', lex('--/*'));
	assert_equals('comment: 8', 'word comment word EOF', lex(q'<asdf/*asdfq'!!'q!'' -- */asdf>'));
	assert_equals('comment: 9a', 'comment EOF', lex('/*'));
	assert_equals('comment: 9b', '-1742', to_char(get_sqlcode_n('/*', 1)));
	assert_equals('comment: 9c', 'comment not terminated properly', get_sqlerrm_n('/*', 1));
end test_comment;


--------------------------------------------------------------------------------
procedure test_text is
begin
	--Simple strings.
	assert_equals('text: simple string 1a', 'whitespace text whitespace EOF', lex(q'! ' ' !'));
	assert_equals('text: simple string 1b', q'!' '!', get_value_n(q'! ' ' !', 2));
	--Simple N strings.
	assert_equals('text: n string 1a', 'whitespace text whitespace EOF', lex(q'! n' ' !'));
	assert_equals('text: n string 1b', q'!n' '!', get_value_n(q'! n' ' !', 2));
	assert_equals('text: n string 2a', 'whitespace text whitespace EOF', lex(q'! N' ' !'));
	assert_equals('text: n string 2b', q'!N' '!', get_value_n(q'! N' ' !', 2));

	--Alternative quoting mechanism closing delimiters: [, {, <, (
	assert_equals('text: alternative quote 1a', 'text EOF', lex(q'!q'[a]'!'));
	assert_equals('text: alternative quote 1b', q'!q'[a]'!', get_value_n(q'!q'[a]'!', 1));
	assert_equals('text: alternative quote 2a', 'text EOF', lex(q'!q'{a}'!'));
	assert_equals('text: alternative quote 2b', q'!q'{a}'!', get_value_n(q'!q'{a}'!', 1));
	assert_equals('text: alternative quote 3a', 'text EOF', lex(q'!q'<a>'!'));
	assert_equals('text: alternative quote 3b', q'!q'<a>'!', get_value_n(q'!q'<a>'!', 1));
	assert_equals('text: alternative quote 4a', 'text EOF', lex(q'!q'(a)'!'));
	assert_equals('text: alternative quote 4b', q'!q'(a)'!', get_value_n(q'!q'(a)'!', 1));
	--Alternative quoting mechanism matching delimiters.
	assert_equals('text: alternative quote ', 'text EOF', lex(q'!q'# ''' #'!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: alternative quote 5b', q'!q'# ''' #'!', get_value_n(q'!q'# ''' #'!', 1)); --'--Fix highlighting on some IDEs.

	--Same as above 2, but for n and N alternative quoting mechanisms.
	assert_equals('text: alternative n quote 1a', 'text EOF', lex(q'!nq'[a]'!'));
	assert_equals('text: alternative n quote 1b', q'!nq'[a]'!', get_value_n(q'!nq'[a]'!', 1));
	assert_equals('text: alternative n quote 2a', 'text EOF', lex(q'!nq'{a}'!'));
	assert_equals('text: alternative n quote 2b', q'!nq'{a}'!', get_value_n(q'!nq'{a}'!', 1));
	assert_equals('text: alternative n quote 3a', 'text EOF', lex(q'!Nq'<a>'!'));
	assert_equals('text: alternative n quote 3b', q'!Nq'<a>'!', get_value_n(q'!Nq'<a>'!', 1));
	assert_equals('text: alternative n quote 4a', 'text EOF', lex(q'!Nq'(a)'!'));
	assert_equals('text: alternative n quote 4b', q'!Nq'(a)'!', get_value_n(q'!Nq'(a)'!', 1));
	assert_equals('text: alternative n quote ', 'text EOF', lex(q'!Nq'# ''' #'!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: alternative n quote 5b', q'!Nq'# ''' #'!', get_value_n(q'!Nq'# ''' #'!', 1)); --'--Fix highlighting on some IDEs.

	--Test string not terminated.
	assert_equals('text: string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer '!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: string not terminated 2', q'!'!', get_value_n(q'!asdf qwer '!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer '!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer '!', 5)); --'--Fix highlighting on some IDEs.
	--Same as above, but for N, alternative quote, and N alternative quote.
	assert_equals('text: n string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer n'!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: n string not terminated 2', q'!n'!', get_value_n(q'!asdf qwer n'!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: n string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer n'!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: n string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer n'!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer Q'<asdf)'''!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 2', q'!Q'<asdf)'''!', get_value_n(q'!asdf qwer Q'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer q'<asdf)'''!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer Q'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 1', 'word whitespace word whitespace text EOF', lex(q'!asdf qwer nQ'<asdf)'''!')); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 2', q'!NQ'<asdf)'''!', get_value_n(q'!asdf qwer NQ'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 3', '-1756', to_char(get_sqlcode_n(q'!asdf qwer nq'<asdf)'''!', 5))); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ string not terminated 4', 'quoted string not properly terminated', get_sqlerrm_n(q'!asdf qwer NQ'<asdf)'''!', 5)); --'--Fix highlighting on some IDEs.

	--Alternative quoting invalid delimiters - they may parse but throw errors.
	--Per my testing, only characters 9, 10, and 32 are problems.  I'm not testing 10 - the quotes are too ugly.
	assert_equals('text: AQ bad delimiter space 1', 'whitespace text whitespace EOF', lex(q'! q'  ' !'));
	assert_equals('text: AQ bad delimiter space 2', q'!q'  '!', get_value_n(q'! q'  ' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter space 3', '-911', to_char(get_sqlcode_n(q'! q'  ' !', 2))); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter space 4', 'invalid character', get_sqlerrm_n(q'! q'  ' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter tab 1', 'whitespace text whitespace EOF', lex(q'! Q'		' !'));
	assert_equals('text: AQ bad delimiter tab 2', q'!Q'		'!', get_value_n(q'! Q'		' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter tab 3', '-911', to_char(get_sqlcode_n(q'! Q'		' !', 2))); --'--Fix highlighting on some IDEs.
	assert_equals('text: AQ bad delimiter tab 4', 'invalid character', get_sqlerrm_n(q'! Q'		' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ bad delimiter space 1', 'whitespace text whitespace EOF', lex(q'! Nq'  ' !'));
	assert_equals('text: NAQ bad delimiter space 2', q'!Nq'  '!', get_value_n(q'! Nq'  ' !', 2)); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ bad delimiter space 3', '-911', to_char(get_sqlcode_n(q'! nq'  ' !', 2))); --'--Fix highlighting on some IDEs.
	assert_equals('text: NAQ bad delimiter space 4', 'invalid character', get_sqlerrm_n(q'! nq'  ' !', 2)); --'--Fix highlighting on some IDEs.
end test_text;


--------------------------------------------------------------------------------
procedure test_numeric is
begin
	assert_equals('numeric: + not part of number', '+ numeric EOF', lex('+1234'));
	assert_equals('numeric: - not part of number', '+ numeric EOF', lex('+1234'));

	assert_equals('numeric: simple integer 1', 'numeric EOF', lex('1234'));
	assert_equals('numeric: simple integer 2', '1234', get_value_n('1234', 1));

	assert_equals('numeric: simple decimal 1', 'numeric EOF', lex('12.34'));
	assert_equals('numeric: simple decimal 2', '12.34', get_value_n('12.34', 1));

	assert_equals('numeric: start with . 1', 'numeric EOF', lex('.1234'));
	assert_equals('numeric: start with . 2', '.1234', get_value_n('.1234', 1));

	assert_equals('numeric: long number 1', 'numeric EOF', lex('1234567890123456789012345678901234567890.1234567890123456789012345678901234567890'));
	assert_equals('numeric: long number 2', '1234567890123456789012345678901234567890.1234567890123456789012345678901234567890', get_value_n('1234567890123456789012345678901234567890.1234567890123456789012345678901234567890', 1));

	assert_equals('numeric: E 1a', 'numeric EOF', lex('1.1e5'));
	assert_equals('numeric: E 1b', '1.1e5', get_value_n('1.1e5', 1));
	assert_equals('numeric: E 2a', 'numeric EOF', lex('1.1e+5'));
	assert_equals('numeric: E 2b', '1.1e+5', get_value_n('1.1e+5', 1));
	assert_equals('numeric: E 3a', 'numeric EOF', lex('1.1e-5'));
	assert_equals('numeric: E 3b', '1.1e-5', get_value_n('1.1e-5', 1));
	--Same as above, but with capital E
	assert_equals('numeric: E 4a', 'numeric EOF', lex('1.1E5'));
	assert_equals('numeric: E 4b', '1.1E5', get_value_n('1.1E5', 1));
	assert_equals('numeric: E 5a', 'numeric EOF', lex('1.1E+5'));
	assert_equals('numeric: E 5b', '1.1E+5', get_value_n('1.1E+5', 1));
	assert_equals('numeric: E 6a', 'numeric EOF', lex('1.1E-5'));
	assert_equals('numeric: E 6b', '1.1E-5', get_value_n('1.1E-5', 1));

	assert_equals('numeric: combine e and d/f 1a', 'numeric EOF', lex('.10e+5d'));
	assert_equals('numeric: combine e and d/f 1b', '.10e+5d', get_value_n('.10e+5d', 1));
	assert_equals('numeric: combine e and d/f 2a', 'numeric EOF', lex('.10E+5D'));
	assert_equals('numeric: combine e and d/f 2b', '.10E+5D', get_value_n('.10E+5D', 1));
	assert_equals('numeric: combine e and d/f 3a', 'numeric EOF', lex('.10E+5f'));
	assert_equals('numeric: combine e and d/f 3b', '.10E+5f', get_value_n('.10E+5f', 1));
	assert_equals('numeric: combine e and d/f 4a', 'numeric EOF', lex('.10e+5F'));
	assert_equals('numeric: combine e and d/f 4b', '.10e+5F', get_value_n('.10e+5F', 1));
	assert_equals('numeric: combine e and d/f 5a', 'numeric EOF', lex('.10e5'));
	assert_equals('numeric: combine e and d/f 5b', '.10e5', get_value_n('.10e5', 1));

	assert_equals('numeric: random 1', 'text numeric EOF', lex(q'[''4]'));
	assert_equals('numeric: random 2', 'numeric + numeric + numeric EOF', lex(q'[4+4+4]'));
	assert_equals('numeric: random 3', 'numeric word EOF', lex(q'[1.2ee]'));
	assert_equals('numeric: random 4', 'numeric word numeric word EOF', lex(q'[1.2ee1.2ff]'));
end test_numeric;


--------------------------------------------------------------------------------
procedure test_word is
begin
	assert_equals('word: simple name', 'word whitespace word EOF', lex('asdf asdf'));

	--Names can include numbers, #, $, and _, but not at the beginning.
	assert_equals('word: identifier 1', 'word EOF', lex('asdfQWER1234#$_asdf'));
	assert_equals('word: identifier 2', 'unexpected word EOF', lex('#a'));
	assert_equals('word: identifier 3', 'preprocessor_control_token EOF', lex('$a'));
	assert_equals('word: identifier 4', 'unexpected word EOF', lex('_a'));
	assert_equals('word: identifier 5', 'numeric word EOF', lex('1a'));
	assert_equals('word: identifier 6', '+ word + EOF', lex('+a1#$_+'));

	--4 byte supplementary character for "cut".
	assert_equals('word: utf8 identifier 1', 'word EOF', lex(g_4_byte_utf8));
	--2 byte D - Latin Capital Letter ETH.
	assert_equals('word: utf8 identifier 2', 'word EOF', lex(g_2_byte_utf8));
	--Putting different letters together.
	assert_equals('word: utf8 identifier 3', 'word + EOF', lex(g_2_byte_utf8||g_2_byte_utf8||g_4_byte_utf8||'A+'));
	assert_equals('word: utf8 identifier 4', g_2_byte_utf8||g_2_byte_utf8||g_4_byte_utf8||'A', get_value_n(g_2_byte_utf8||g_2_byte_utf8||g_4_byte_utf8||'A+', 1));

	assert_equals('word: double quote 1', 'word word EOF', lex('"asdf"a'));
	assert_equals('word: double quote 2', 'word word EOF', lex('"!@#$%^&*()"a'));
	assert_equals('word: double quote 3', '"!@#$%^&*()"', get_value_n('"!@#$%^&*()"a', 1));
	assert_equals('word: double quote 4', 'word numeric word EOF', lex('"a"4"b"'));

	assert_equals('word: missing double quote 1a', 'word EOF', lex('"!@#$%^&*()'));
	assert_equals('word: missing double quote 1b', '-1740', get_sqlcode_n('"!@#$%^&*()', 1));
	assert_equals('word: missing double quote 1c', 'missing double quote in identifier', get_sqlerrm_n('"!@#$%^&*()', 1));

	--This should be an error, but must be enforced later by the parser.
	assert_equals('word: zero-length identifier 1a', 'numeric word EOF', lex('1""'));
	assert_equals('word: zero-length identifier 1b', '""', get_value_n('1""', 2));
	assert_equals('word: zero-length identifier 1c', null, get_sqlcode_n('1""', 2));
	assert_equals('word: zero-length identifier 1d', null, get_sqlerrm_n('1""', 2));

	assert_equals('word: identifier is too long 30 bytes 1a', 'word EOF', lex('abcdefghijabcdefghijabcdefghij'));
	assert_equals('word: identifier is too long 30 bytes 1b', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghij', 1));
	assert_equals('word: identifier is too long 30 bytes 1c', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghij', 1));
	assert_equals('word: identifier is too long 30 bytes 2a', 'word EOF', lex('"abcdefghijabcdefghijabcdefghij"'));
	assert_equals('word: identifier is too long 30 bytes 2b', null, get_sqlcode_n('"abcdefghijabcdefghijabcdefghij"', 1));
	assert_equals('word: identifier is too long 30 bytes 2c', null, get_sqlerrm_n('"abcdefghijabcdefghijabcdefghij"', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('word: identifier is too long 31 bytes 1a', 'word EOF', lex('abcdefghijabcdefghijabcdefghijK'));
	assert_equals('word: identifier is too long 31 bytes 1b', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghijK', 1));
	assert_equals('word: identifier is too long 31 bytes 1c', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghijK', 1));
	assert_equals('word: identifier is too long 31 bytes 2a', 'word EOF', lex('"abcdefghijabcdefghijabcdefghijK"'));
	assert_equals('word: identifier is too long 31 bytes 2b', null, get_sqlcode_n('"abcdefghijabcdefghijabcdefghijK"', 1));
	assert_equals('word: identifier is too long 31 bytes 2c', null, get_sqlerrm_n('"abcdefghijabcdefghijabcdefghijK"', 1));

	assert_equals('word: identifier is too long 29 chars 31 bytes 1a', 'word EOF', lex('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8));
	assert_equals('word: identifier is too long 29 chars 31 bytes 1b', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));
	assert_equals('word: identifier is too long 29 chars 31 bytes 1c', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));

	--Database links can have 128 bytes.  This example is valid.
	assert_equals('word: database link 1', 'word whitespace * whitespace word whitespace word @ word . word @ word EOF', lex('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij.abcdefghijabcdefghijabcdefghijabcdefghij@abcdefghijabcdefghijabcdefghijabcdefghij'));
	assert_equals('word: database link 2', '@', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 8));
	assert_equals('word: database link 3', 'abcdefghijabcdefghijabcdefghijabcdefghij1', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 9));
	assert_equals('word: database link 4', '.', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 10));
	assert_equals('word: database link 5', 'abcdefghijabcdefghijabcdefghijabcdefghij2', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 11));
	assert_equals('word: database link 6', '@', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 12));
	assert_equals('word: database link 7', 'abcdefghijabcdefghijabcdefghijabcdefghij3', get_value_n('select * from dual@abcdefghijabcdefghijabcdefghijabcdefghij1.abcdefghijabcdefghijabcdefghijabcdefghij2@abcdefghijabcdefghijabcdefghijabcdefghij3', 13));
	assert_equals('word: database link 8', null, get_sqlcode_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));
	assert_equals('word: database link 9', null, get_sqlerrm_n('abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, 1));
end test_word;


--------------------------------------------------------------------------------
procedure test_inquiry_directive is
begin
	assert_equals('inquiry directive: simple 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$asdf); end;'));
	assert_equals('inquiry directive: simple 2', '$$asdf', get_value_n('begin dbms_output.put_line($$asdf); end;', 7));

	assert_equals('inquiry directive: name characters 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$asdf$_#1); end;'));
	assert_equals('inquiry directive: name characters 2', '$$asdf$_#1', get_value_n('begin dbms_output.put_line($$asdf$_#1); end;', 7));

	assert_equals('inquiry directive: unexpected (empty name)', 'word whitespace word . word ( unexpected unexpected ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$); end;'));

	assert_equals('inquiry directive: 30 characters 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghij); end;'));
	assert_equals('inquiry directive: 30 characters 2', '$$abcdefghijabcdefghijabcdefghij', get_value_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghij); end;', 7));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('inquiry directive: 31 characters 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghijK); end;'));
	assert_equals('inquiry directive: 31 characters 2', null, get_sqlcode_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghijK); end;', 1));
	assert_equals('inquiry directive: 31 characters 3', null, get_sqlerrm_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghijK); end;', 1));

	--PL/SQL Bug(?): Inquiry directive can be over 31 bytes if the last character starts before byte 30.
	assert_equals('inquiry directive: 30 characters 31 bytes 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('inquiry directive: 30 characters 31 bytes 2', '$$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, get_value_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 7));
	assert_equals('inquiry directive: 30 characters 31 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('inquiry directive: 30 characters 31 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('inquiry directive: 30 characters 33 bytes 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;'));
	assert_equals('inquiry directive: 30 characters 33 bytes 2', '$$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8, get_value_n('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 7));
	assert_equals('inquiry directive: 30 characters 33 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));
	assert_equals('inquiry directive: 30 characters 33 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('inquiry directive: 30 characters 31 bytes 1', 'word whitespace word . word ( inquiry_directive ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('inquiry directive: 30 characters 31 bytes2', null, get_sqlcode_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('inquiry directive: 30 characters 31 bytes3', null, get_sqlerrm_n('begin dbms_output.put_line($$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
end test_inquiry_directive;


--------------------------------------------------------------------------------
procedure test_preproc_control_token is
begin
	assert_equals('preprocessor control token: valid example 1', 'word whitespace preprocessor_control_token whitespace numeric = numeric whitespace preprocessor_control_token whitespace word ; whitespace preprocessor_control_token whitespace word ; EOF', lex('begin $if 1=1 $then null; $end end;'));
	assert_equals('preprocessor control token: valid example 2', 'begin', get_value_n('begin $if 1=1 $then null; $end end;', 1));
	assert_equals('preprocessor control token: valid example 3', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 2));
	assert_equals('preprocessor control token: valid example 4', '$if', get_value_n('begin $if 1=1 $then null; $end end;', 3));
	assert_equals('preprocessor control token: valid example 5', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 4));
	assert_equals('preprocessor control token: valid example 6', '1', get_value_n('begin $if 1=1 $then null; $end end;', 5));
	assert_equals('preprocessor control token: valid example 7', '=', get_value_n('begin $if 1=1 $then null; $end end;', 6));
	assert_equals('preprocessor control token: valid example 8', '1', get_value_n('begin $if 1=1 $then null; $end end;', 7));
	assert_equals('preprocessor control token: valid example 9', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 8));
	assert_equals('preprocessor control token: valid example 10', '$then', get_value_n('begin $if 1=1 $then null; $end end;', 9));
	assert_equals('preprocessor control token: valid example 11', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 10));
	assert_equals('preprocessor control token: valid example 12', 'null', get_value_n('begin $if 1=1 $then null; $end end;', 11));
	assert_equals('preprocessor control token: valid example 13', ';', get_value_n('begin $if 1=1 $then null; $end end;', 12));
	assert_equals('preprocessor control token: valid example 14', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 13));
	assert_equals('preprocessor control token: valid example 15', '$end', get_value_n('begin $if 1=1 $then null; $end end;', 14));
	assert_equals('preprocessor control token: valid example 16', ' ', get_value_n('begin $if 1=1 $then null; $end end;', 15));
	assert_equals('preprocessor control token: valid example 17', 'end', get_value_n('begin $if 1=1 $then null; $end end;', 16));
	assert_equals('preprocessor control token: valid example 18', ';', get_value_n('begin $if 1=1 $then null; $end end;', 17));
	assert_equals('preprocessor control token: valid example 19', '', get_value_n('begin $if 1=1 $then null; $end end;', 18));

	assert_equals('preprocessor control token: name characters 1', 'word whitespace preprocessor_control_token whitespace numeric = numeric whitespace preprocessor_control_token whitespace word ; whitespace preprocessor_control_token whitespace word ; EOF', lex('begin $if_#$1 1=1 $then null; $end end;'));
	assert_equals('preprocessor control token: name characters 2', '$if_#$1', get_value_n('begin $if_#$1 1=1 $then null; $end end;', 3));

	assert_equals('preprocessor control token: unexpected (empty name)', 'word whitespace word . word ( unexpected ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($); end;'));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('preprocessor control token: 31 characters 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghijK); end;'));
	assert_equals('preprocessor control token: 31 characters 2', null, get_sqlcode_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghijK); end;', 1));
	assert_equals('preprocessor control token: 31 characters 3', null, get_sqlerrm_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghijK); end;', 1));

	--PL/SQL Bug(?): Preprocessor control tokens can be over 31 bytes if the last character starts before byte 30.
	--Although all preprocessor control tokens are predefined.  Using anything else will throw an additional error.
	--It may not be worth catching this second error.
	assert_equals('preprocessor control token: 30 characters 31 bytes 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('preprocessor control token: 30 characters 31 bytes 2', '$abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8, get_value_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 7));
	assert_equals('preprocessor control token: 30 characters 31 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('preprocessor control token: 30 characters 31 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('preprocessor control token: 30 characters 33 bytes 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;'));
	assert_equals('preprocessor control token: 30 characters 33 bytes 2', '$'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8, get_value_n('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 7));
	assert_equals('preprocessor control token: 30 characters 33 bytes 3', null, get_sqlcode_n('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));
	assert_equals('preprocessor control token: 30 characters 33 bytes 4', null, get_sqlerrm_n('begin dbms_output.put_line($'||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||'); end;', 1));

	--These should be errors, but must be enforced later by the parser.
	assert_equals('preprocessor control token: 30 characters 31 bytes 1', 'word whitespace word . word ( preprocessor_control_token ) ; whitespace word ; EOF', lex('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;'));
	assert_equals('preprocessor control token: 30 characters 31 bytes2', null, get_sqlcode_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
	assert_equals('preprocessor control token: 30 characters 31 bytes3', null, get_sqlerrm_n('begin dbms_output.put_line($abcdefghijabcdefghijabcdefghi'||g_2_byte_utf8||'); end;', 1));
end test_preproc_control_token;


--------------------------------------------------------------------------------
procedure test_3_character_punctuation is
begin
	assert_equals('3-char punctuation: 01', ', , ,}? , , EOF', lex(q'[,,,}?,,]'));

	assert_equals('3-char punctuation: 02', ',', get_value_n(q'[,,,}?,,]', 1));
	assert_equals('2-char punctuation: 03', ',', get_value_n(q'[,,,}?,,]', 2));
	assert_equals('2-char punctuation: 04', ',}?', get_value_n(q'[,,,}?,,]', 3));
	assert_equals('2-char punctuation: 05', ',', get_value_n(q'[,,,}?,,]', 4));
	assert_equals('2-char punctuation: 06', ',', get_value_n(q'[,,,}?,,]', 5));
end test_3_character_punctuation;


--------------------------------------------------------------------------------
procedure test_2_character_punctuation is
begin
	--TODO: Add row pattern quantifiers.
	assert_equals('2-char punctuation: 01', '~= != ^= <> := => >= <= ** || << >> EOF', lex(q'[~=!=^=<>:==>>=<=**||<<>>]'));

	assert_equals('2-char punctuation: 02', '~=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 1));
	assert_equals('2-char punctuation: 03', '!=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 2));
	assert_equals('2-char punctuation: 04', '^=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 3));
	assert_equals('2-char punctuation: 05', '<>', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 4));
	assert_equals('2-char punctuation: 06', ':=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 5));
	assert_equals('2-char punctuation: 07', '=>', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 6));
	assert_equals('2-char punctuation: 08', '>=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 7));
	assert_equals('2-char punctuation: 09', '<=', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 8));
	assert_equals('2-char punctuation: 10', '**', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 9));
	assert_equals('2-char punctuation: 11', '||', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 10));
	assert_equals('2-char punctuation: 12', '<<', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 11));
	assert_equals('2-char punctuation: 13', '>>', get_value_n(q'[~=!=^=<>:==>>=<=**||<<>>]', 12));
end test_2_character_punctuation;


--------------------------------------------------------------------------------
procedure test_1_character_punctuation is
begin
	--TODO: Add row pattern quantifiers.
	assert_equals('1-char punctuation: 01', '@ % * ( ) - + = [ ] : ; < , > . / EOF', lex(q'[@%*()-+=[]:;<,>./]'));

	assert_equals('1-char punctuation: 02', '@', get_value_n(q'[@%*()-+=[]:;<,>./]', 1));
	assert_equals('1-char punctuation: 03', '%', get_value_n(q'[@%*()-+=[]:;<,>./]', 2));
	assert_equals('1-char punctuation: 04', '*', get_value_n(q'[@%*()-+=[]:;<,>./]', 3));
	assert_equals('1-char punctuation: 05', '(', get_value_n(q'[@%*()-+=[]:;<,>./]', 4));
	assert_equals('1-char punctuation: 06', ')', get_value_n(q'[@%*()-+=[]:;<,>./]', 5));
	assert_equals('1-char punctuation: 07', '-', get_value_n(q'[@%*()-+=[]:;<,>./]', 6));
	assert_equals('1-char punctuation: 08', '+', get_value_n(q'[@%*()-+=[]:;<,>./]', 7));
	assert_equals('1-char punctuation: 09', '=', get_value_n(q'[@%*()-+=[]:;<,>./]', 8));
	assert_equals('1-char punctuation: 10', '[', get_value_n(q'[@%*()-+=[]:;<,>./]', 9));
	assert_equals('1-char punctuation: 11', ']', get_value_n(q'[@%*()-+=[]:;<,>./]', 10));
	assert_equals('1-char punctuation: 12', ':', get_value_n(q'[@%*()-+=[]:;<,>./]', 11));
	assert_equals('1-char punctuation: 13', ';', get_value_n(q'[@%*()-+=[]:;<,>./]', 12));
	assert_equals('1-char punctuation: 14', '<', get_value_n(q'[@%*()-+=[]:;<,>./]', 13));
	assert_equals('1-char punctuation: 15', ',', get_value_n(q'[@%*()-+=[]:;<,>./]', 14));
	assert_equals('1-char punctuation: 16', '>', get_value_n(q'[@%*()-+=[]:;<,>./]', 15));
	assert_equals('1-char punctuation: 17', '.', get_value_n(q'[@%*()-+=[]:;<,>./]', 16));
	assert_equals('1-char punctuation: 18', '/', get_value_n(q'[@%*()-+=[]:;<,>./]', 17));

	assert_equals('1-char punctuation: 241',
		'<< word >> word whitespace word whitespace word := numeric ; whitespace word whitespace word ; whitespace word ; EOF',
		lex(q'[<<my_label>>declare v_test number:=1; begin null; end;]'));
end test_1_character_punctuation;


--------------------------------------------------------------------------------
procedure test_unexpected is
begin
	assert_equals('unexpected: 01', 'unexpected EOF', lex('_'));
	assert_equals('unexpected: 02', '_', get_value_n('_', 1));
	assert_equals('unexpected: 03', 'word unexpected EOF', lex('abcd&'));
	assert_equals('unexpected: 04', '&', get_value_n('abcd&', 2));
end test_unexpected;


--------------------------------------------------------------------------------
procedure test_utf8 is
begin
	--Try to trip-up substrings with multiples of that character.
	assert_equals('utf8: 4-byte 1', 'word EOF', lex(g_4_byte_utf8));
	assert_equals('utf8: 4-byte 2', 'word whitespace word EOF', lex(g_4_byte_utf8 || ' ' || g_4_byte_utf8));
	assert_equals('utf8: 4-byte 4', 'word whitespace word EOF', lex(g_4_byte_utf8||g_4_byte_utf8||g_4_byte_utf8||' a'));
	assert_equals('utf8: 4-byte 3', 'word whitespace word EOF', lex(g_4_byte_utf8||g_4_byte_utf8||'asdf'||g_4_byte_utf8||' a'));
end test_utf8;


--------------------------------------------------------------------------------
procedure test_other is
begin
	assert_equals('Other: Null only returns EOF', 'EOF', lex(null));
	assert_equals('Other: EOF value is NULL', null, get_value_n(null, 1));
	assert_equals('Other: Random', 'word whitespace - numeric + numeric whitespace word whitespace word ; EOF', lex('select -1+1e2d from dual;'));
end test_other;


--------------------------------------------------------------------------------
procedure dynamic_tests is
	type clob_table is table of clob;
	type string_table is table of varchar2(100);
	v_sql_fulltexts clob_table;
	v_sql_ids string_table;
	sql_cursor sys_refcursor;
	v_throwaway nclob;
begin
	--This is a test against infinite loops.

	--TODO: There should not be any unexpected tokens.

	open sql_cursor for '
		--Select distinct SQL statements.
		select sql_fulltext, sql_id
		from
		(
			select sql_fulltext, sql_id, row_number() over (partition by sql_id order by 1) rownumber
			from gv$sql
		)
		where rownumber = 1
		order by sql_id
	';
	loop
		fetch sql_cursor bulk collect into v_sql_fulltexts, v_sql_ids limit 100;
		exit when v_sql_fulltexts.count = 0;

		for i in 1 .. v_sql_fulltexts.count loop
			dbms_output.put_line('SQL_ID: '||v_sql_ids(i));
			assert_equals('just incrementing counter', 'a', 'a');
			v_throwaway := lex(v_sql_fulltexts(i));
		end loop;
	end loop;
end dynamic_tests;


--------------------------------------------------------------------------------
procedure run(p_tests number default c_all_static_tests) is
begin
	--Reset counters.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;

	--Run the chosen tests.
	if bitand(p_tests, c_test_whitespace)              > 0 then test_whitespace; end if;
	if bitand(p_tests, c_test_comment)                 > 0 then test_comment; end if;
	if bitand(p_tests, c_test_text)                    > 0 then test_text; end if;
	if bitand(p_tests, c_test_numeric)                 > 0 then test_numeric; end if;
	if bitand(p_tests, c_test_word)                    > 0 then test_word; end if;
	if bitand(p_tests, c_test_inquiry_directive)       > 0 then test_inquiry_directive; end if;
	if bitand(p_tests, c_test_preproc_control_token)   > 0 then test_preproc_control_token; end if;
	if bitand(p_tests, c_test_3_character_punctuation) > 0 then test_3_character_punctuation; end if;
	if bitand(p_tests, c_test_2_character_punctuation) > 0 then test_2_character_punctuation; end if;
	if bitand(p_tests, c_test_1_character_punctuation) > 0 then test_1_character_punctuation; end if;
	if bitand(p_tests, c_test_unexpected)              > 0 then test_unexpected; end if;
	if bitand(p_tests, c_test_utf8)                    > 0 then test_utf8; end if;
	if bitand(p_tests, c_test_other)                   > 0 then test_other; end if;
	if bitand(p_tests, c_dynamic_tests)                > 0 then dynamic_tests; end if;


	--Print summary of results.
	dbms_output.put_line(null);
	dbms_output.put_line('----------------------------------------');
	dbms_output.put_line('PL/SQL Lexer Test Summary');
	dbms_output.put_line('----------------------------------------');
	dbms_output.put_line('Total : '||g_test_count);
	dbms_output.put_line('Passed: '||g_passed_count);
	dbms_output.put_line('Failed: '||g_failed_count);

	--Print easy to read pass or fail message.
	if g_failed_count = 0 then
		dbms_output.put_line('
  _____         _____ _____ 
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___  
 |  ___/ /\ \  \___ \\___ \ 
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/');
	else
		dbms_output.put_line('
  ______      _____ _      
 |  ____/\   |_   _| |     
 | |__ /  \    | | | |     
 |  __/ /\ \   | | | |     
 | | / ____ \ _| |_| |____ 
 |_|/_/    \_\_____|______|');
	end if;
end run;

end;
/
