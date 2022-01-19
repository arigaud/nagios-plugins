'Script to check the status of a DOMAIN controller and report to Nagios
'requires DCDIAG.EXE 
'Author: Felipe Ferreira
'Version: 3.3-20220119

'
'Mauled over by John Jore, j-o-h-n-a-t-j-o-r-e-d-o-t-n-o 16/11/2010 to work on W2K8, x32
'as well as remove some, eh... un-needed lines of code, general optimization as well as adding command parameter support
'This is where i found the original script, http://felipeferreira.net/?p=315&cpage=1#comments
'Tested by JJ on W2K8 SP2, x86
'		 W2K3 R2 SP2, x64
'Version 3.0-JJ-V0.2
'Todo: Proper error handling
'      Add support for the two tests which require additional input (dcpromo is one such test)
'Version 3.0-JJ-V0.3
'	Removed some surplus language detection code
'		Including non-working English test on a W2K8 x32 DC
'	Added support for multi-partition checks like 'crossrefvalidation'. Previously the last status result would mask previous failures
'	Incorporated Jonathan Vogt's german and multiline tests
'Version 3.0-DAE-V0.4
'	Added support for DNS test parameters (dns /dnsbasic /dnsdelegation)
'	Fix problem to alert status NotOk
'Version 3.0-PAR-V0.5
'   Fix multiline parsing
'   Added connectivity, sysvol, and kccevent tests
'       and "dns /dnsbasic" check on 2008 and later
'   Tested on Windows 2003, 2008 R2, and 2012 R2 DCs
'Version 3.1-20150304 by Alexandre Rigaud
'   Parsed Guillaume ONA's detection of code page with French support and help parameter
'	Source : https://github.com/Guiona/NagiosPlugins
'   Tested on Windows 2003 (ENG), 2008 R2 (FR/ENG), and 2012 R2 (ENG) DCs
'Version 3.2-20151105 by Alexandre Rigaud
'   Added check dcdiag.exe is on system32 folder
'	Added Spanish support (not tested) 
'Version 3.3-20160630 by Alexandre Rigaud
'   Fix issue on french characters 
'Version 3.3-20220119 by Nikola Uvalic
'   Fix issue on false positive for FSMOCHECK for long domain names (tested on server 2019)

'Force all variables to be declared before usage
option explicit

'Array for name and status (Ugly, but redim only works on last dimension, and can't set initial size if redim 
dim name(), status()
redim preserve name(0)
redim preserve status(0)
redim preserve lock(0)

'Debug switch
dim verbose : verbose = 0

'Return variables for NAGIOS
const intOK = 0
const intWarning = 1 'Not used. What dcdiag test would be warning instead of critical?
const intCritical = 2
const intUnknown = 3

'Lang dependend. Default is english
dim strOK : strOK = "passed "
dim strNotOK : strNotOk = "failed "

'Check if dcidag command exists on system32 folder
dim filesys,path_dcdiag
Set filesys = CreateObject("Scripting.FileSystemObject")

path_dcdiag = "c:\windows\system32\dcdiag.exe"
if not(filesys.FileExists (path_dcdiag)) then
	wscript.echo "The system cannot find the file specified: " & path_dcdiag
	wscript.quit(intCritical)
end if

'Call dcdiag and grab relevant output
exec(cmd)

'Generate NAGIOS compatible output from dcdiag
printout()

'call dcdiag and parse the output
sub exec(strCmd)
	'Declare variables
	dim objShell : Set objShell = WScript.CreateObject("WScript.Shell")
	dim oExec1 : Set oExec1=objShell.Exec("cmd /c chcp")
	dim conv : Set conv=CreateObject("OlePrn.OleCvt")
	dim objExecObject, lineout, tmpline, mess, ssaccent
	dim page_code
	lineout = ""
	'Command line options we're using
	pt strCmd 
    mess=oExec1.StdOut.ReadAll
	page_code = Split(mess,":",-1,1)
	Set objExecObject = objShell.Exec(strCmd)
	'Loop until end of output from dcdiag
	do While not objExecObject.StdOut.AtEndOfStream
        ssaccent = conv.ToUnicode(objExecObject.StdOut.ReadLine(),trim(page_code(1)))
		tmpline = lcase(ssaccent)
		'Check the version of DCDiag being used and change the global 'passed' / 'failed' strings
		call parselang(tmpline)
		lineout = lineout + tmpline
		if (instr(tmpline, ".....")) then 
			'testresults start with a couple of dots, so lets reset the lineout buffer
			lineout= tmpline
		end if
		if instr(lineout, lcase(strOK)) then
			'we have a strOK String which means we have reached the end of a result output (maybe on newline)
			call parse(lineout)
			lineout = ""
		end if 
	loop
	' Catch the very last test (may be in the lineout buffer but not yet processed)
	if instr(lineout, lcase(strOK) & " test") OR instr(lineout, lcase(strNotOK) & " test") then
	    'we have a strOK String which means we have reached the end of a result output (maybe on newline)
	    call parse(lineout)
	end if
end sub

sub parselang(txtp)
    txtp = Replace(txtp,chr(10),"") ' Newline
	txtp = Replace(txtp,chr(13),"") ' CR
	txtp = Replace(txtp,chr(9),"")  ' Tab
	do while instr(txtp, "  ")
		txtp = Replace(txtp,"  "," ") ' Some tidy up
	loop
	
	if (instr(lcase(txtp), lcase("Domain Controller Diagnosis"))) then ' English
		strOK = "passed"
		strNotOk = "failed"
	elseif (instr(lcase(txtp), lcase("Verzeichnisserverdiagnose"))) then ' German
		strOK = "bestanden"
		strNotOk = "nicht bestanden"
	elseif (instr(lcase(txtp), lcase("Diagnostic du serveur d'annuaire"))) then ' French
		dim conv : Set conv=CreateObject("OlePrn.OleCvt")
		strOK = conv.ToUnicode("r" & chr(130) & "ussi",1)
		strNotOk = conv.ToUnicode(chr(130) & "chou" & chr(130),1)
	elseif (instr(lcase(txtp), lcase("Configuración inicial de Diagnosis"))) then ' Spanish
		strOK = "pasa"
		strNotOk = "fallida"
	end if	
end sub

sub parse(txtp)
	'Parse output of dcdiag command and change state of checks
	dim loop1
	dim strname
    'Is this really required? Or is it for pretty debug output only?
	txtp = Replace(txtp,chr(10),"") ' Newline
	txtp = Replace(txtp,chr(13),"") ' CR
	txtp = Replace(txtp,chr(9),"")  ' Tab
	do while instr(txtp, "  ")
	  txtp = Replace(txtp,"  "," ") ' Some tidy up
	loop
    pt "txtp=" & txtp
	' We have to test twice because some localized (e.g. German) outputs simply use 'not', or 'nicht' as a prefix instead of 'passed' / 'failed'

	for loop1 = 0 to Ubound(name)-1

		if instr(lcase(txtp), lcase(strOK)) then
			'What are we testing for now?
			pt "Checking :" & txtp & "' as it contains '" & strOK & "'"

			'What services are ok? 'By using instr we don't need to strip down text, remove vbCr, VbLf, or get the hostname
			for each strname in split(lcase(name(loop1)))


				if (instr(lcase(txtp), strname)) AND (lock(loop1) = FALSE) then 
					status(loop1)="OK"
					pt "Set the status for test '" & name(loop1) & "' to '" & status(loop1) & "'"
				end if

			next
		end if

		' if we find the strNotOK string then reset to CRITICAL
		if instr(lcase(txtp), lcase(strNotOK)) then
			'What are we testing for now?
			pt txtp
			for each strname in split(lcase(name(loop1)))

				if (instr(lcase(txtp), strname)) then 
					status(loop1)="CRITICAL"
					'Lock the variable so it can't be reset back to success. Required for multi-partition tests like 'crossrefvalidation'
					lock(loop1)=TRUE
					pt "Reset the status for test '" & name(loop1) & "' to '" & status(loop1) & "' with a lock '" & lock(loop1) & "'"
				end if
			next
		end if

	next


end sub

'outputs result for NAGIOS
sub printout()
	dim loop1, msg : msg = ""

	for loop1 = 0 to ubound(name)-1
		msg = msg & name(loop1) & ": " & status(loop1) & ". "
	next

	'What state are we in? Show and then quit with NAGIOS compatible exit code
	if instr(msg,"CRITICAL") then
		wscript.echo "CRITICAL - " & msg
		wscript.quit(intCritical)
	else
		wscript.echo "OK - " & msg
		wscript.quit(intOK)
	end if
end sub

'Print messages to screen for debug purposes
sub pt(msgTxt)
	if verbose then
		wscript.echo msgTXT
	end if
end sub

' get OS version so we can do correct sysvol check
function osVer()
  dim shell, getOSversion, version
  set shell = CreateObject("Wscript.Shell")
  set getOSversion = shell.exec("%comspec% /c ver")
  version = getOSversion.stdout.readall  
  if InStr(version, "n 5.") > 1 then
    osVer = 5
  else
    osVer = 6
  end if
end function

'What tests do we run?
function cmd()
	dim loop1, test, tests, os, intDefaultTests
	os = osVer()
	if os = 5 then
	  intDefaultTests = 9
	else
	  intDefaultTests = 10
	end if
	cmd = "dcdiag " 'Start with this

	'If no command line parameters, then go with these defaults
	if Wscript.Arguments.Count = 0 Then
		redim preserve name(intDefaultTests)
		redim preserve status(intDefaultTests)
		redim preserve lock(intDefaultTests)
		'Test name
		name(0) = "connectivity"
		name(1) = "services"
		name(2) = "replications"
		name(3) = "advertising"
		name(4) = "fsmocheck"
		name(5) = "ridmanager"
		name(6) = "machineaccount"
		name(7) = "kccevent"
		if os = 5 then
			name(8) = "frssysvol"
		else
			name(8) = "sysvolcheck"
			name(9) = "dns /dnsbasic"		
		end if

		' "frsevent"   (or dfrsevent 2008 & 2012)

		'Set default status for each named test


		for loop1 = 0 to (ubound(name)-1)
			status(loop1) = "CRITICAL"
			lock(loop1) = FALSE
			cmd = cmd & "/test:" & name(loop1) & " "
		next
	else
		'User need help

		if lcase(wscript.Arguments(loop1)) = "/help" then
			    wscript.echo "Usage : (with or without //nologo)" & VbCrLf & _
			        "        This script require dcdiag.exe " & VbCrLf & _
			        "        cscript.exe check_ad.vbs //nologo" & VbCrLf & _
			        "        cscript.exe check_ad.vbs //nologo /test:services" & VbCrLf & _
			        "        cscript.exe check_ad.vbs /test:services,fsmocheck,machineaccount" & VbCrLf & VbCrLf & _
				" ..::: For valid check, execute the script without arguments :::.."

			    wscript.quit(intUnknown)
		end if
		'User specified which tests to perform.

		for loop1 = 0 to wscript.arguments.count - 1
			if (instr(lcase(wscript.Arguments(loop1)), lcase("/test"))) then
			
			'If parameter is wrong, give some hints
			if len(wscript.arguments(loop1)) < 6 then
				wscript.echo "Unknown parameter. Provide name of tests to perform like this:"
				wscript.echo vbTAB & "'cscript //nologo " & Wscript.ScriptName & " /test:advertising,dfsevent'"

				wscript.quit(intUnknown)
			end if
			
			'Strip down the test to individual items
			tests = right(wscript.arguments(loop1), len(wscript.arguments(loop1))-6)
			pt "Tests: '" & tests & "'"

			tests = split(tests,",")
			for each test in tests

				cmd = cmd  & " /test:" & test

				'Expand the array to make room for one more test
				redim preserve name(ubound(name)+1)
				redim preserve status(ubound(status)+1)
				redim preserve lock(ubound(lock)+1)

				'Store name of test and status
				name(Ubound(name)-1) = test
				status(Ubound(status)-1) = "CRITICAL" 'Default status. Change to OK if test is ok
				lock(Ubound(lock)-1) = FALSE 'Don't lock the variable yet.

				pt "Contents: " & name(Ubound(name)-1) & " " & status(Ubound(status)-1)
			next
			else
			    wscript.echo "UNKNOWN - Invalid arguments :" & wscript.Arguments(loop1) & " , use /help for list of valid arguments"
			    wscript.quit(intUnknown)
			end if
		next
	end if
	'We end up with this to test:
	pt "Command to run: " & cmd
end function
