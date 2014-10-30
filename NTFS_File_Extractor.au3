#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Res_Fileversion=4.0.0.5
#AutoIt3Wrapper_Res_requestedExecutionLevel=asInvoker
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#Include <WinAPIEx.au3>
#Include <FileConstants.au3>
#include <permissions.au3>
#include <array.au3>
Local $Version = "v4.0.0.5"
;
; https://github.com/jschicht
; http://code.google.com/p/mft2csv/
;
; by Joakim Schicht & Ddan
; parts by trancexxx & others

;General disclaimer. This application may construct files with super long filenames which
;may not be deletable by normal means. If you do not know how to handle such files, maybe
;you should not use this application. In any event, don't ring me.

Global Const $GUI_EVENT_CLOSE = -3
Global Const $GUI_CHECKED = 1
Global Const $GUI_UNCHECKED = 4
Global Const $ES_AUTOVSCROLL = 64
Global Const $WS_VSCROLL = 0x00200000
Global Const $DT_END_ELLIPSIS = 0x8000
Global Const $FILE_OPEN_REPARSE_POINT = 0x00200000
Global Const $FSCTL_SET_REPARSE_POINT = 0x000900A4
Global Const $FILE_FLAG_BACKUP_SEMANTICS = 0x02000000

Global $TargetDrive = "", $MFT_Record_Size, $BytesPerCluster, $MFT_Offset, $MFT_Size, $LogicalClusterNumberforthefileMFT, $SectorsPerCluster, $BytesPerSector, $SectorsPerMftRecord, $ClustersPerFileRecordSegment, $MftAttrListString
Global $FileTree[1], $hDisk, $rBuffer, $NonResidentFlag, $zPath, $sBuffer, $Total, $SplitMftRecArr[1]
Global $FN_FileName, $ADS_Name, $Reparse = ""
Global $DATA_LengthOfAttribute, $DATA_Clusters, $DATA_RealSize, $DATA_InitSize, $DataRun
Global $IsCompressed, $IsSparse, $subset, $logfile = 0, $subst, $active = False
Global $RUN_VCN[1], $RUN_Clusters[1], $MFT_RUN_Clusters[1], $MFT_RUN_VCN[1], $DataQ[1], $AttrQ[1]
Global $TargetImageFile, $Entries, $IsImage = False, $ImageOffset=0
Global $begin, $ElapsedTime, $UserRefInput, $UserRefArray[1]
Global $OverallProgress, $FileProgress, $CurrentProgress, $ProgressStatus, $ProgressFileName, $ProgressSize, $ComboPhysicalDrives, $IsPhysicalDrive=False, $IsShadowCopy=False

Global Const $RecordSignature = '46494C45' ; FILE signature
Global $outputpath = @scriptdir

Opt("GUIOnEventMode", 1)  ; Change to OnEvent mode

$Form = GUICreate("NTFS File Extractor " & $Version, 560, 450, -1, -1)
GUISetOnEvent($GUI_EVENT_CLOSE, "_HandleExit", $Form)

$Combo = GUICtrlCreateCombo("", 20, 30, 390, 20)
$ComboPhysicalDrives = GUICtrlCreateCombo("", 180, 3, 305, 20)
$buttonScanPhysicalDrives = GUICtrlCreateButton("Scan Physical", 5, 3, 80, 20)
GUICtrlSetOnEvent($buttonScanPhysicalDrives, "_HandleEvent")
$buttonScanShadowCopies = GUICtrlCreateButton("Scan Shadows", 90, 3, 80, 20)
GUICtrlSetOnEvent($buttonScanShadowCopies, "_HandleEvent")
$buttonTestPhysicalDrive = GUICtrlCreateButton("<-- Test it", 495, 3, 60, 20)
GUICtrlSetOnEvent($buttonTestPhysicalDrive, "_HandleEvent")
$buttonDrive = GUICtrlCreateButton("Rescan Mounted Drives", 425, 30, 130, 20)
GUICtrlSetOnEvent($buttonDrive, "_HandleEvent")
$buttonImage = GUICtrlCreateButton("Choose Image", 440, 60, 100, 20)
GUICtrlSetOnEvent($buttonImage, "_HandleEvent")
$buttonOutput = GUICtrlCreateButton("Choose Output", 440, 90, 100, 20)
GUICtrlSetOnEvent($buttonOutput, "_HandleEvent")
$buttonStart = GUICtrlCreateButton("Start Extraction", 230, 60, 120, 20)
GUICtrlSetOnEvent($buttonStart, "_HandleEvent")
$myctredit = GUICtrlCreateEdit("Extracting files from NTFS formatted volume" & @CRLF, 0, 150, 560, 125, $ES_AUTOVSCROLL + $WS_VSCROLL)
_DisplayInfo("Default Output Folder is " & $outputpath & @CRLF)
;_GetPhysicalDrives(PhysicalDrive)
_GetMountedDrivesInfo()

GUIStartGroup()
$radioAll = GUICtrlCreateRadio("All", 30, 50, 70, 20)
$radioDel = GUICtrlCreateRadio("Deleted", 30, 75, 70, 20)
$radioAct = GUICtrlCreateRadio("Active", 30, 100, 70, 20)
$radioUser = GUICtrlCreateRadio("User Select", 30, 125, 70, 20)
GUICtrlSetState($radioAll, $GUI_CHECKED)

GUIStartGroup()
$radioLog = GUICtrlCreateRadio("Logfile", 130, 50, 60, 20)
GUICtrlSetState($radioLog, $GUI_CHECKED)
$LogState = True
GUICtrlSetOnEvent($radioLog, "_HandleEvent")

GUIStartGroup()
$radioInit = GUICtrlCreateRadio("Partial Init", 130, 75, 60, 20)
$InitState = False
GUICtrlSetOnEvent($radioInit, "_HandleEvent")

GUISetState(@SW_SHOW, $Form)

While Not $active
   Sleep(1000)	;Wait for event
WEnd

$TimestampStart = @YEAR & "-" & @MON & "-" & @MDAY & "_" & @HOUR & "-" & @MIN & "-" & @SEC
If GUICtrlRead($radioLog) = $GUI_CHECKED Then $logfile = FileOpen(@ScriptDir & "\" & $TimestampStart & ".log",2)
If GUICtrlRead($radioAll) = $GUI_CHECKED Then
   $subset = 0
   _DisplayInfo("TargetFiles are All files" & @CRLF)
ElseIf GUICtrlRead($radioDel) = $GUI_CHECKED Then
   $subset = -1
   _DisplayInfo("TargetFiles are All Deleted files" & @CRLF)
ElseIf GUICtrlRead($radioAct) = $GUI_CHECKED Then
   $subset = 1
   _DisplayInfo("TargetFiles are All Active files" & @CRLF)
Else
   $UserRefInput = InputBox("User Selected File Set", "Enter comma separated list of file mft reference numbers", "")
   If Not $UserRefInput Then Exit
   $UserRefArray = StringSplit($UserRefInput,",")
   $subset = -2
   _DisplayInfo("TargetFiles are a User Selected set of files" & @CRLF)
EndIf
_DebugOut("Operation started: " & $TimestampStart)

Select
	Case $IsImage = True
		$TargetDrive = "Img"
		$ImageOffset = Int(StringMid(GUICtrlRead($Combo),10),2)
		_DisplayInfo(@CRLF & "Target is: " & GUICtrlRead($Combo) & @CRLF)
		_DebugOut("Target is: " & $TargetImageFile)
		_DebugOut("Volume at offset: " & $ImageOffset)
		$hDisk = _WinAPI_CreateFile($TargetImageFile,2,2,7)
		If $hDisk = 0 Then _DebugOut("CreateFile: " & _WinAPI_GetLastErrorMessage())
	Case $IsPhysicalDrive = True
		$TargetDrive = "PD"&StringMid($TargetImageFile,18)
		$ImageOffset = Int(StringMid(GUICtrlRead($Combo),10),2)
		_DebugOut("Target drive is: " & $TargetImageFile)
		_DebugOut("Volume at offset: " & $ImageOffset)
		$hDisk = _WinAPI_CreateFile($TargetImageFile,2,2,7)
		If $hDisk = 0 Then _DebugOut("CreateFile: " & _WinAPI_GetLastErrorMessage())
	Case $IsShadowCopy = True
		$TargetDrive = "SC"&StringMid($TargetImageFile,47)
		$ImageOffset = Int(StringMid(GUICtrlRead($Combo),10),2)
		_DebugOut("Target drive is: " & $TargetImageFile)
		_DebugOut("Volume at offset: " & $ImageOffset)
		$hDisk = _WinAPI_CreateFile($TargetImageFile,2,2,7)
		If $hDisk = 0 Then _DebugOut("CreateFile: " & _WinAPI_GetLastErrorMessage())
	Case Else
		$TargetDrive = StringMid(GUICtrlRead($Combo),1,1)
		_DebugOut("Target drive is: " & $TargetDrive & ":")
		$hDisk = _WinAPI_CreateFile("\\.\" & $TargetDrive&":",2,2,7)
		If $hDisk = 0 Then _DebugOut("CreateFile: " & _WinAPI_GetLastErrorMessage())
EndSelect

$begin1 = TimerInit()
_ExtractSystemfile()
_DebugOut("Total extraction time is " & _WinAPI_StrFromTimeInterval(TimerDiff($begin1)))
_WinAPI_CloseHandle($hDisk)
If $logfile Then FileClose($logfile)
$active = False
Exit

Func _HandleEvent()
	If Not $active Then
		Switch @GUI_CTRLID
			Case $buttonDrive
				_GetMountedDrivesInfo()
				$IsImage = False
				$IsShadowCopy = False
				$IsPhysicalDrive = False
			Case $buttonImage
				_ProcessImage()
				$IsImage = True
				$IsShadowCopy = False
				$IsPhysicalDrive = False
			Case $buttonOutput
				$newoutputpath = FileSelectFolder("Select output folder.", "",7,$outputpath)
				If Not @error then
					_DisplayInfo("New output folder: " & $newoutputpath & @CRLF)
				EndIf
				If StringRight($newoutputpath,1) = "\" Then
					$outputpath = StringTrimRight($newoutputpath,1)
				Else
					$outputpath = $newoutputpath
				EndIf
			Case $buttonStart
				$active = True
			Case $radioLog
				$LogState = Not $LogState
				If $LogState = False Then GUICtrlSetState($radioLog, $GUI_UNCHECKED)
			Case $radioInit
				$InitState = Not $InitState
				If $InitState = False Then GUICtrlSetState($radioInit, $GUI_UNCHECKED)
			Case $buttonScanPhysicalDrives
				_GetPhysicalDrives("PhysicalDrive")
				$IsShadowCopy = False
				$IsPhysicalDrive = True
				$IsImage = False
			Case $buttonScanShadowCopies
				_GetPhysicalDrives("GLOBALROOT\Device\HarddiskVolumeShadowCopy")
				$IsShadowCopy = True
				$IsPhysicalDrive = False
				$IsImage = False
			Case $buttonTestPhysicalDrive
				_TestPhysicalDrive()
		EndSwitch
	EndIf
EndFunc

Func _HandleExit()
	If $logfile Then FileClose($logfile)
	If $hDisk Then _WinAPI_CloseHandle($hDisk)
	Exit
EndFunc

Func _ExtractSystemfile()
   Global $DataQ[1], $RUN_VCN[1], $RUN_Clusters[1]		;redefine arrays
   If $IsImage=False And $IsPhysicalDrive=False And $IsShadowCopy=False Then
	  If DriveGetFileSystem($TargetDrive&":") <> "NTFS" Then		;read boot sector and extract $MFT data
		 _DebugOut("Error: Target volume " & $TargetDrive & " is not NTFS")
		 Return
	  EndIf
	  _DisplayInfo("Target volume is: " & $TargetDrive&":" & @crlf)
   EndIf

   _WinAPI_SetFilePointerEx($hDisk, $ImageOffset, $FILE_BEGIN)
   $BootRecord = _GetDiskConstants()
   If $BootRecord = "" Then
	  _DebugOut("Unable to read Boot Sector")
	  Return
   EndIf
   $rBuffer = DllStructCreate("byte[" & $MFT_Record_Size & "]")     ;buffer for records

   $MFT = _ReadMFT()
   If $MFT = "" Then Return		;something wrong with record for $MFT

   $MFT = _DecodeMFTRecord0($MFT, 0)        ;produces DataQ for $MFT, record 0
   If $MFT = "" Then Return

   _GetRunsFromAttributeListMFT0() ;produces datarun for $MFT and converts datarun to RUN_VCN[] and RUN_Clusters[]

   $MFT_Size = $Data_RealSize

   $MFT_RUN_VCN = $RUN_VCN
   $MFT_RUN_Clusters = $RUN_Clusters	;preserve values for $MFT

   $Progress = GUICtrlCreateLabel("File Extraction Progress", 10, 250,540,20)
   GUICtrlSetFont($Progress, 12)
   $ProgressStatus = GUICtrlCreateLabel("", 10, 280, 540, 20)
   $ElapsedTime = GUICtrlCreateLabel("", 10, 295, 540, 20)
   $OverallProgress = GUICtrlCreateProgress(10, 320, 540, 30)

   _DoFileTree()                        ;creates folder structure

   $ProgressFileName = GUICtrlCreateLabel("", 10,  360, 540, 20, $DT_END_ELLIPSIS)
   $FileProgress = GUICtrlCreateProgress(10, 385, 540, 30)
   AdlibRegister("_ExtractionProgress", 500)
   $begin = TimerInit()

   If $subset = -2 Then		;user selected files
	  For $i = 1 To $UserRefArray[0]
		 $CurrentProgress = $i
		 Local $mft = $UserRefArray[$i]
		 If StringIsDigit($mft) And $mft < UBound($FileTree) Then
			If StringInStr($Filetree[$mft], "?") > 0 Then
			   _DoExtraction($mft)		;only files
			Else
			   _DisplayInfo("Not extracted, fileref is Folder: " & $mft & @crlf)
			   _DebugOut("Not extracted, fileref is Folder: " & $mft)
			EndIf
		 Else
			_DisplayInfo("Not extracted, invalid fileref: " & $mft & @crlf)
			_DebugOut("Not extracted, invalid fileref: " & $mft)
		EndIf
	  Next
   Else
	  For $i = 0 To UBound($FileTree)-1	;note $i is mft reference number
		 $CurrentProgress = $i
		 If ($i > 15 AND $i < 24) Or ($i = 8) Then ContinueLoop		;exclude $BadClus (has volume size ADS)
		 If $subset < 0 And StringInStr($Filetree[$i], "[DEL") = 0 Then ContinueLoop
		 If $subset > 0 And StringInStr($Filetree[$i], "[DEL") > 0 Then ContinueLoop
		 If StringInStr($Filetree[$i], "?") = 0 Then	;not file
			If StringInStr($FileTree[$i],":") > 0 Then DirCreate($FileTree[$i])
			ContinueLoop
		 EndIf
		 _DoExtraction($i)
	  Next
   EndIf
   If $Reparse <> "" Then _DoReparsePoints()
   _WinAPI_CloseHandle($hDisk)
   AdlibUnRegister()
   GUIDelete($Progress)
   _DisplayInfo("Finished extraction of files." & @crlf & @crlf)
   _DebugOut("Finished extraction of files.")
EndFunc

Func _DoExtraction($MftRef)
	Local $nBytes, $Names[1], $Files = $Filetree[$MftRef]
;	_DebugOut("$Files: " & $Files)
	If StringInStr($Files, "*") > 0 Then		;must be hard links
		$pos = StringMid($Files, StringInStr($Files, "?") + 1)
		$pos = StringMid($pos, 1,StringInStr($pos, "*") - 1)
		$str = StringReplace($Files, "?" & $pos, "")
		$Names = StringSplit($str, "*")
		$Files = $Names[1] & "?" & $pos
	EndIf
	If StringInStr($Files, "/") > 0 Then ;MFT record was split across 2 dataruns
		_DebugOut("Ref " & $MftRef & " has its record split across 2 dataruns")
		$SplitRecordPart1 = StringMid($Files, StringInStr($Files, "/")+1)
		$SplitRecordPart2 = $SplitMftRecArr[$SplitRecordPart1]
		$SplitRecordTestRef = StringMid($SplitRecordPart2, 1, StringInStr($SplitRecordPart2, "?")-1)
		If $SplitRecordTestRef <> $MftRef Then ;then something is not quite right
			_DebugOut("Error: The ref in the array did not match target ref.")
			Return
		EndIf
		$SplitRecordPart3 = StringMid($SplitRecordPart2, StringInStr($SplitRecordPart2, "?")+1)
		$SplitRecordArr = StringSplit($SplitRecordPart3,"|")
		If UBound($SplitRecordArr) <> 3 Then
			_DebugOut("Error: Array contained more elements than expected: " & UBound($SplitRecordArr))
			Return
		EndIf
		$record="0x"
		For $k = 1 To Ubound($SplitRecordArr)-1
			$SplitRecordOffset = StringMid($SplitRecordArr[$k], 1, StringInStr($SplitRecordArr[$k], ",")-1)
			$SplitRecordSize = StringMid($SplitRecordArr[$k], StringInStr($SplitRecordArr[$k], ",")+1)
			_WinAPI_SetFilePointerEx($hDisk, $ImageOffset+$SplitRecordOffset, $FILE_BEGIN)
			$kBuffer = DllStructCreate("byte["&$SplitRecordSize&"]")
			_WinAPI_ReadFile($hDisk, DllStructGetPtr($kBuffer), $SplitRecordSize, $nBytes)
			$record &= StringMid(DllStructGetData($kBuffer,1),3)
			$kBuffer=0
		Next
;		ConsoleWrite(_HexEncode($record) & @CRLF)
	Else
		_WinAPI_SetFilePointerEx($hDisk, $ImageOffset+StringMid($Files, StringInStr($Files, "?") + 1), $FILE_BEGIN)
		_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
		$record = DllStructGetData($rBuffer, 1)
	EndIf
	$FN_FileName = StringMid($Files, 1,StringInStr($Files, "?") - 1)
	If StringMid($record,3,8) <> $RecordSignature Then
		_DebugOut($MftRef & " The record signature is bad 1", StringMid($record, 1, 66))
;		_DebugOut($MftRef & " The record signature is bad 1", $record)
		Return
	EndIf
	_ExtractSingleFile($record, $MftRef)
	If $Names[0] > 1 Then
		For $n = 2 to $Names[0]
			$zflag = 0
			Do
				DirCreate(StringMid($Names[$n], 1, StringInStr($Names[$n], "\", 0, -1)))
				$err = FileCreateNTFSLink($FN_FileName, $Names[$n],1)	;make hard links
				If Not $err Then
					If $zflag = 0 Then		;first pass
						$mid = Int(StringLen($Names[$n])/2)
						$zPath = StringMid($Names[$n], 1, StringInStr($Names[$n], "\", 0, -1, $mid)-1)
					ElseIf $zflag = 1 Then		;second pass
						$ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
						$Names[$n] = StringReplace($Names[$n],$subst, $zPath)	;restore full name
						$zPath = StringMid($Names[$n], 1, StringInStr($Names[$n], "\", 0, 1, $mid)-1)
					Else		;fail
						_DebugOut("Error creating hardlink for " & StringReplace($Names[$n],$subst,$zPath), $record)
						$ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
						ExitLoop
					EndIf
					$ret = _WinAPI_DefineDosDevice($subst, 0, $zPath)     ;open spare
					$Names[$n] = StringReplace($Names[$n],$zPath, $subst)
					$zflag += 1
				EndIf
			Until $err
		Next
	EndIf
EndFunc

Func _ExtractSingleFile($MFTRecord, $FileRef)
   Global $DataQ[1]				;clear array
   $MFTRecord = _DecodeMFTRecord($MFTRecord, $FileRef)
   If $MFTRecord = "" Then Return	;error so finish
   If UBound($DataQ) = 1 Then
	  _DebugOut($FileRef & " No $DATA attribute for the file: " & $FN_FileName, $MFTRecord)
	  Return
   EndIf
   For $i = 1 To UBound($DataQ) - 1
	  _DecodeDataQEntry($DataQ[$i])
	  If $ADS_Name = "" Then
		 _DebugOut($FileRef & " No $NAME attribute for the file",$MFTRecord)
		 Return
	  EndIf
	  If $NonResidentFlag = '00' Then
		 _ExtractResidentFile($ADS_Name, $DATA_LengthOfAttribute, $MFTRecord)
	  Else
		 Global $RUN_VCN[1], $RUN_Clusters[1]
		 $TotalClusters = $Data_Clusters
		 $RealSize = $DATA_RealSize		;preserve file sizes
		 If Not $InitState Then $DATA_InitSize = $DATA_RealSize
		 $InitSize = $DATA_InitSize
		 _ExtractDataRuns()
		 If $TotalClusters * $BytesPerCluster >= $RealSize Then
			_ExtractFile($MFTRecord)
		 Else 		 ;code to handle attribute list
			$Flag = $IsCompressed		;preserve compression state
			For $j = $i + 1 To UBound($DataQ) -1
			   _DecodeDataQEntry($DataQ[$j])
			   $TotalClusters += $Data_Clusters
			   _ExtractDataRuns()
			   If $TotalClusters * $BytesPerCluster >= $RealSize Then
				  $DATA_RealSize = $RealSize		;restore file sizes
				  $DATA_InitSize = $InitSize
				  $IsCompressed = $Flag		;recover compression state
				  _ExtractFile($MFTRecord)
				  ExitLoop
			   EndIf
			Next
			$i = $j
		 EndIf
	  EndIf
   Next
EndFunc

Func _PrintRuns()
	;Just for informational purpose
	Local $nBytes,$MFTClustersToKeep=0,$Div=$MFT_Record_Size/512,$MFTClustersToKeep=0
	For $t = 1 To Ubound($MFT_RUN_VCN)-1
		ConsoleWrite($t & ": $MFT_RUN_Clusters[$t]: " & $MFT_RUN_Clusters[$t] & " $MFT_RUN_VCN[$t]: " & $MFT_RUN_VCN[$t] & @CRLF)
	Next
	ConsoleWrite(@CRLF)
	For $t = 1 To Ubound($MFT_RUN_VCN)-1
		$MFTClustersToKeep = Mod($MFT_RUN_Clusters[$t]+($ClustersPerFileRecordSegment-$MFTClustersToKeep),$ClustersPerFileRecordSegment)
		If $MFTClustersToKeep <> 0 Then
			$MFTClustersToKeep = $ClustersPerFileRecordSegment - $MFTClustersToKeep
			ConsoleWrite($t & " run. $MFT_RUN_Clusters[$t]: " & $MFT_RUN_Clusters[$t] & " Mod: " & $MFTClustersToKeep & @CRLF)
			ConsoleWrite(@CRLF)
		EndIf
	Next
	ConsoleWrite(@CRLF)
	For $t = 1 To Ubound($MFT_RUN_VCN)-1
		$Pos = $MFT_RUN_VCN[$t]*$BytesPerCluster
		_WinAPI_SetFilePointerEx($hDisk, $ImageOffset+$Pos, $FILE_BEGIN)
		_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)

		$record = DllStructGetData($rBuffer, 1)
		If StringMid($record,3,8) <> $RecordSignature Then
			_DebugOut($t & " run. The record signature is bad _PrintRuns()", StringMid($record, 1, 34))
			ContinueLoop
		EndIf
	Next
	Exit
EndFunc

Func _DoFileTree()
	Local $nBytes, $ParentRef, $FileRef, $BaseRef, $tag, $PrintName, $record, $TmpRecord, $MFTClustersToKeep=0, $DoKeepCluster=0, $Subtr, $PartOfAttrList=0, $ArrSize
	$Total = Int($MFT_Size/$MFT_Record_Size)
	Global $FileTree[$Total]
;	_PrintRuns()
	$ref = -1
	AdlibRegister("_DoFileTreeProgress", 500)
	$begin = TimerInit()
	For $r = 1 To Ubound($MFT_RUN_VCN)-1
;		ConsoleWrite("$r: " & $r & @CRLF)
		$DoKeepCluster=$MFTClustersToKeep
		$MFTClustersToKeep = Mod($MFT_RUN_Clusters[$r]+($ClustersPerFileRecordSegment-$MFTClustersToKeep),$ClustersPerFileRecordSegment)
		If $MFTClustersToKeep <> 0 Then
			$MFTClustersToKeep = $ClustersPerFileRecordSegment - $MFTClustersToKeep ;How many clusters are we missing to get the full MFT record
		EndIf
		$Pos = $MFT_RUN_VCN[$r]*$BytesPerCluster
		_WinAPI_SetFilePointerEx($hDisk, $ImageOffset+$Pos, $FILE_BEGIN)
		If $MFTClustersToKeep Or $DoKeepCluster Then
			$Subtr = 0
		Else
			$Subtr = $MFT_Record_Size
		EndIf
		$EndOfRun = $MFT_RUN_Clusters[$r]*$BytesPerCluster-$Subtr
		For $i = 0 To $MFT_RUN_Clusters[$r]*$BytesPerCluster-$Subtr Step $MFT_Record_Size
			If $MFTClustersToKeep Then
				If $i >= $EndOfRun-(($ClustersPerFileRecordSegment-$MFTClustersToKeep)*$BytesPerCluster) Then
					$BytesToGet = ($ClustersPerFileRecordSegment-$MFTClustersToKeep)*$BytesPerCluster
					$CurrentOffset = DllCall('kernel32.dll', 'int', 'SetFilePointerEx', 'ptr', $hDisk, 'int64', 0, 'int64*', 0, 'dword', 1)
					_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $BytesToGet, $nBytes)
					$TmpRecord = StringMid(DllStructGetData($rBuffer, 1),1, 2+($BytesToGet*2))
					$ArrSize = UBound($SplitMftRecArr)
					ReDim $SplitMftRecArr[$ArrSize+1]
					$SplitMftRecArr[$ArrSize] = $ref+1 & '?' & $CurrentOffset[3] & ',' & $BytesToGet
					ContinueLoop
				EndIf
			EndIf
			$ref += 1
			$CurrentProgress = $ref
			If $i = 0 And $DoKeepCluster Then
				If $TmpRecord <> "" Then $record = $TmpRecord
				$BytesToGet = $DoKeepCluster*$BytesPerCluster
				if $BytesToGet > $MFT_Record_Size Then
					MsgBox(0,"Error","$BytesToGet > $MFT_Record_Size")
					$BytesToGet = $MFT_Record_Size
				EndIf
				$CurrentOffset = DllCall('kernel32.dll', 'int', 'SetFilePointerEx', 'ptr', $hDisk, 'int64', 0, 'int64*', 0, 'dword', 1)
				_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $BytesToGet, $nBytes)
				$record &= StringMid(DllStructGetData($rBuffer, 1),3, $BytesToGet*2)
				$TmpRecord=""
				$SplitMftRecArr[$ArrSize] &= '|' & $CurrentOffset[3] & ',' & $BytesToGet
			Else
				$CurrentOffset = DllCall('kernel32.dll', 'int', 'SetFilePointerEx', 'ptr', $hDisk, 'int64', 0, 'int64*', 0, 'dword', 1)
				_WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
				$record = DllStructGetData($rBuffer, 1)
			EndIf
			If StringMid($record,3,8) <> $RecordSignature Then
				_DebugOut($ref & " The record signature is bad _DoFileTree()", StringMid($record, 1, 34))
				ContinueLoop
			EndIf
			$Flags = Dec(StringMid($record,47,4))
			$record = _DoFixup($record, $ref)
			If $record = "" then ContinueLoop   ;corrupt, failed fixup
			$FileRef = $ref
			$BaseRef = Dec(_SwapEndian(StringMid($record,67,8)),2)
			If $BaseRef <> 0 Or StringInStr($MftAttrListString,','&$FileRef&',') Then ;The baseRef can be 0 for the extra records when $MFT contains $ATTRIBUTE_LIST
				$FileTree[$FileRef] = $Pos + $i      ;may contain data attribute
				$FileRef = $BaseRef
				$PartOfAttrList=1
			Else
				$PartOfAttrList=0
			EndIf
			$Offset = (Dec(StringMid($record,43,2))*2)+3
			$FileName = ""
			While 1     ;only want names and reparse
				$Type = Dec(StringMid($record,$Offset,8),2)
				If $Type > Dec("C0000000",2) Then ExitLoop   ;no more names or reparse
				$Size = Dec(_SwapEndian(StringMid($record,$Offset+8,8)),2)
				If $Type = Dec("30000000",2) Then
					$attr = StringMid($record,$Offset,$Size*2)
					$ParentRef = Dec(_SwapEndian(StringMid($attr,49,8)),2)
					$NameSpace = StringMid($attr,179,2)
					If $NameSpace <> "02" Then
						$NameLength = Dec(StringMid($attr,177,2))
						$FileName = StringMid($attr,181,$NameLength*4)
						$FileName = _UnicodeHexToStr($FileName)
						If Not BitAND($Flags,Dec("0100")) Then $FileName = "[DEL" & $ref & "]" & $FileName     ;deleted record
						$FileTree[$FileRef] &= "**" & $ParentRef & "*" & $FileName
					EndIf
				ElseIf $Type = Dec("C0000000",2) Then
					$tag = StringMid($record,$Offset + 48,8)
					$PrintNameOffset = Dec(_SwapEndian(StringMid($record,$Offset+72,4)),2)
					$PrintNameLength = Dec(_SwapEndian(StringMid($record,$Offset+76,4)),2)
					If $tag = "030000A0" Then	;JUNCTION
						$PrintName = _UnicodeHexToStr(StringMid($record, $Offset+80+$PrintNameOffset*2, $PrintNameLength*2))
					ElseIf $tag = "0C0000A0" Then	;SYMLINKD
						$PrintName = _UnicodeHexToStr(StringMid($record, $Offset+80+$PrintNameOffset*2+8, $PrintNameLength*2))
					Else
						_DebugOut($ref & " Unhandled Reparse Tag: " & $tag, $record)
					EndIf
					$Reparse &= $ref & "*" & $tag & "*" & $PrintName & "?"
				EndIf
				$Offset += $Size*2
			WEnd

;			If Not BitAND($Flags,Dec("0200")) And $PartOfAttrList=0 And $FileTree[$FileRef] <> "" Then $FileTree[$FileRef] &= "?" & ($Pos + $i)     ;file also add FilePointer
			If Not BitAND($Flags,Dec("0200")) And $PartOfAttrList=0 And $FileTree[$FileRef] <> "" Then $FileTree[$FileRef] &= "?" & ($CurrentOffset[3])     ;file also add FilePointer
			If StringInStr($FileTree[$FileRef], "**") = 1 Then $FileTree[$FileRef] = StringTrimLeft($FileTree[$FileRef],2)    ;remove leading **
			If $i = 0 And $DoKeepCluster Then $FileTree[$FileRef] &= "/" & $ArrSize  ;Mark record as being split across 2 runs
		Next
	Next
	AdlibUnRegister()
	$FileTree[5] = $outputpath & "\" & $TargetDrive
	$begin = TimerInit()
	AdlibRegister("_FolderStrucProgress", 500)
	For $i = 0 to UBound($FileTree)-1
		$CurrentProgress = $i
		If StringInStr($FileTree[$i], "**") = 0 Then
			While StringInStr($FileTree[$i], "*") > 0   ;single file
				$Parent=StringMid($Filetree[$i], 1, StringInStr($FileTree[$i], "*")-1)
				If StringInStr($Filetree[$Parent],"?")=0 And (StringInStr($Filetree[$Parent],"*")>0 Or StringInStr($Filetree[$Parent],":")>0) Then
					$FileTree[$i] = StringReplace($FileTree[$i], $Parent & "*", $Filetree[$Parent] & "\")
				Else
					$FileTree[$i] = StringReplace($FileTree[$i], $Parent & "*", $Filetree[5] & "\ORPHAN\")
				EndIf
			WEnd
		Else
			$Names = StringSplit($FileTree[$i], "**",3)     ;hard links
			$str = ""
			For $n = 0 to UBound($Names) - 1
				While StringInStr($Names[$n], "*") > 0
					$Parent=StringMid($Names[$n], 1, StringInStr($Names[$n], "*")-1)
					If StringInStr($Filetree[$Parent],"?")=0 And (StringInStr($Filetree[$Parent],"*")>0 Or StringInStr($Filetree[$Parent],":")>0) Then
						$Names[$n] = StringReplace($Names[$n], $Parent & "*", $Filetree[$Parent] & "\")
					Else
						$Names[$n] = StringReplace($Names[$n], $Parent & "*", $Filetree[5] & "\ORPHAN\")
					EndIf
				WEnd
				$str &= $Names[$n] & "*"
			Next
			$FileTree[$i] = StringTrimRight($str,1)
		EndIf
	Next
	AdlibUnRegister()
;	_ArrayDisplay($SplitMftRecArr,"$SplitMftRecArr")
EndFunc

Func _DecodeAttrList($FileRef, $AttrList)
   Local $offset, $length, $nBytes, $List = "", $str = ""
   If StringMid($AttrList, 17, 2) = "00" Then		;attribute list is resident in AttrList
	  $offset = Dec(_SwapEndian(StringMid($AttrList, 41, 4)))
	  $List = StringMid($AttrList, $offset*2+1)		;gets list when resident
   Else			;attribute list is found from data run in $AttrList
	  $size = Dec(_SwapEndian(StringMid($AttrList, $offset*2 + 97, 16)))
	  $offset = ($offset + Dec(_SwapEndian(StringMid($AttrList, $offset*2 + 65, 4))))*2
	  $DataRun = StringMid($AttrList, $offset+1, StringLen($AttrList)-$offset)
	  Global $RUN_VCN[1], $RUN_Clusters[1]		;redim arrays
	  _ExtractDataRuns()
	  $cBuffer = DllStructCreate("byte[" & $BytesPerCluster & "]")
	  For $r = 1 To Ubound($RUN_VCN)-1
		 _WinAPI_SetFilePointerEx($hDisk, $ImageOffset+$RUN_VCN[$r]*$BytesPerCluster, $FILE_BEGIN)
		 For $i = 1 To $RUN_Clusters[$r]
			_WinAPI_ReadFile($hDisk, DllStructGetPtr($cBuffer), $BytesPerCluster, $nBytes)
			$List &= StringTrimLeft(DllStructGetData($cBuffer, 1),2)
		 Next
	  Next
	  $List = StringMid($List, 1, $size*2)
   EndIf
   If StringMid($List, 1, 8) <> "10000000" Then Return ""		;bad signature
   $offset = 0
   While StringLen($list) > $offset*2
	  $ref = Dec(_SwapEndian(StringMid($List, $offset*2 + 33, 8)))
	  If $ref <> $FileRef Then		;new attribute
		 If Not StringInStr($str, $ref) Then $str &= $ref & "-"
	  EndIf
	  $offset += Dec(_SwapEndian(StringMid($List, $offset*2 + 9, 4)))
   WEnd
   $AttrQ[0] = ""
   If $str <> "" Then $AttrQ = StringSplit(StringTrimRight($str,1), "-")
   Return $List
EndFunc

Func _StripMftRecord($record, $FileRef)
   $record = _DoFixup($record, $FileRef)
   If $record = "" then Return ""  ;corrupt, failed fixup
   $RecordSize = Dec(_SwapEndian(StringMid($record,51,8)),2)
   $HeaderSize = Dec(_SwapEndian(StringMid($record,43,4)),2)
   $record = StringMid($record,$HeaderSize*2+3,($RecordSize-$HeaderSize-8)*2)        ;strip "0x..." and "FFFFFFFF..."
   Return $record
EndFunc

Func _ExtractDataRuns()
   $r=UBound($RUN_Clusters)
   ReDim $RUN_Clusters[$r + $MFT_Record_Size], $RUN_VCN[$r + $MFT_Record_Size]
   $i=1
   $RUN_VCN[0] = 0
   $BaseVCN = $RUN_VCN[0]
   If $DataRun = "" Then $DataRun = "00"
   Do
	  $RunListID = StringMid($DataRun,$i,2)
	  If $RunListID = "00" Then ExitLoop
	  $i += 2
	  $RunListClustersLength = Dec(StringMid($RunListID,2,1))
	  $RunListVCNLength = Dec(StringMid($RunListID,1,1))
	  $RunListClusters = Dec(_SwapEndian(StringMid($DataRun,$i,$RunListClustersLength*2)),2)
	  $i += $RunListClustersLength*2
	  $RunListVCN = _SwapEndian(StringMid($DataRun, $i, $RunListVCNLength*2))
	  ;next line handles positive or negative move
	  $BaseVCN += Dec($RunListVCN,2)-(($r>1) And (Dec(StringMid($RunListVCN,1,1))>7))*Dec(StringMid("10000000000000000",1,$RunListVCNLength*2+1),2)
	  If $RunListVCN <> "" Then
		 $RunListVCN = $BaseVCN
	  Else
		 $RunListVCN = 0
	  EndIf
	  If (($RunListVCN=0) And ($RunListClusters>16) And (Mod($RunListClusters,16)>0)) Then
		 ;may be sparse section at end of Compression Signature
		 $RUN_Clusters[$r] = Mod($RunListClusters,16)
		 $RUN_VCN[$r] = $RunListVCN
		 $RunListClusters -= Mod($RunListClusters,16)
		 $r += 1
	  ElseIf (($RunListClusters>16) And (Mod($RunListClusters,16)>0)) Then
		 ;may be compressed data section at start of Compression Signature
		 $RUN_Clusters[$r] = $RunListClusters-Mod($RunListClusters,16)
		 $RUN_VCN[$r] = $RunListVCN
		 $RunListVCN += $RUN_Clusters[$r]
		 $RunListClusters = Mod($RunListClusters,16)
		 $r += 1
	  EndIf
	  ;just normal or sparse data
	  $RUN_Clusters[$r] = $RunListClusters
	  $RUN_VCN[$r] = $RunListVCN
	  $r += 1
	  $i += $RunListVCNLength*2
   Until $i > StringLen($DataRun)
   ReDim $RUN_Clusters[$r], $RUN_VCN[$r]
EndFunc

Func _DecodeDataQEntry($attr)		;processes data attribute
   $NonResidentFlag = StringMid($attr,17,2)
   $NameLength = Dec(StringMid($attr,19,2))
   $NameOffset = Dec(_SwapEndian(StringMid($attr,21,4)))
   If $NameLength > 0 Then		;must be ADS
	  $ADS_Name = _UnicodeHexToStr(StringMid($attr,$NameOffset*2 + 1,$NameLength*4))
	  $ADS_Name = $FN_FileName & "[ADS_" & $ADS_Name & "]"
   Else
	  $ADS_Name = $FN_FileName		;need to preserve $FN_FileName
   EndIf
   $Flags = StringMid($attr,25,4)
   If BitAND($Flags,"0100") Then $IsCompressed = 1
   If BitAND($Flags,"0080") Then $IsSparse = 1
   If $NonResidentFlag = '01' Then
	  $DATA_Clusters = Dec(_SwapEndian(StringMid($attr,49,16)),2) - Dec(_SwapEndian(StringMid($attr,33,16)),2) + 1
	  $DATA_RealSize = Dec(_SwapEndian(StringMid($attr,97,16)),2)
	  $DATA_InitSize = Dec(_SwapEndian(StringMid($attr,113,16)),2)
	  $Offset = Dec(_SwapEndian(StringMid($attr,65,4)))
	  $DataRun = StringMid($attr,$Offset*2+1,(StringLen($attr)-$Offset)*2)
   ElseIf $NonResidentFlag = '00' Then
	  $DATA_LengthOfAttribute = Dec(_SwapEndian(StringMid($attr,33,8)),2)
	  $Offset = Dec(_SwapEndian(StringMid($attr,41,4)))
	  $DataRun = StringMid($attr,$Offset*2+1,$DATA_LengthOfAttribute*2)
   EndIf
EndFunc

Func _DecodeMFTRecord0($record, $FileRef)      ;produces DataQ
	$MftAttrListString=","
	$record = _DoFixup($record, $FileRef)
	If $record = "" then Return ""  ;corrupt, failed fixup
	$RecordSize = Dec(_SwapEndian(StringMid($record,51,8)),2)
	$AttributeOffset = (Dec(StringMid($record,43,2))*2)+3
	While 1		;only want Attribute List and Data Attributes
		$Type = Dec(_SwapEndian(StringMid($record,$AttributeOffset,8)),2)
		If $Type > 256 Then ExitLoop		;attributes may not be in numerical order
		$AttributeSize = Dec(_SwapEndian(StringMid($record,$AttributeOffset+8,8)),2)
		If $Type = 32 Then
			$AttrList = StringMid($record,$AttributeOffset,$AttributeSize*2)	;whole attribute
			$AttrList = _DecodeAttrList($FileRef, $AttrList)		;produces $AttrQ - extra record list
			If $AttrList = "" Then
				_DebugOut($FileRef & " Bad Attribute List signature", $record)
				Return ""
			Else
				If $AttrQ[0] = "" Then ContinueLoop		;no new records
				$str = ""
				For $i = 1 To $AttrQ[0]
					$MftAttrListString &= $AttrQ[$i] & ","
;					ConsoleWrite("$AttrQ[$i]: " & $AttrQ[$i] & @CRLF)
					If Not IsNumber(Int($AttrQ[$i])) Then
						_DebugOut($FileRef & " Overwritten extra record (" & $AttrQ[$i] & ")", $record)
						Return ""
					EndIf
					$rec = _GetAttrListMFTRecord(($AttrQ[$i]*$MFT_Record_Size)+($LogicalClusterNumberforthefileMFT*$BytesPerCluster))
					If StringMid($rec,3,8) <> $RecordSignature Then
						_DebugOut($FileRef & " Bad signature for extra record", $record)
						Return ""
					EndIf
					If Dec(_SwapEndian(StringMid($rec,67,8)),2) <> $FileRef Then
						_DebugOut($FileRef & " Bad extra record", $record)
						Return ""
					EndIf
					$rec = _StripMftRecord($rec, $FileRef)
					If $rec = "" Then
						_DebugOut($FileRef & " Extra record failed Fixup", $record)
						Return ""
					EndIf
					$str &= $rec		;no header or end marker
				Next
				$record = StringMid($record,1,($RecordSize-8)*2+2) & $str & "FFFFFFFF"       ;strip end first then add
			EndIf
		ElseIf $Type = 128 Then
			ReDim $DataQ[UBound($DataQ) + 1]
			$DataQ[UBound($DataQ) - 1] = StringMid($record,$AttributeOffset,$AttributeSize*2) 		;whole data attribute
		EndIf
		$AttributeOffset += $AttributeSize*2
	WEnd
	Return $record
EndFunc

Func _DecodeMFTRecord($record, $FileRef)      ;produces DataQ
	$record = _DoFixup($record, $FileRef)
	If $record = "" then Return ""  ;corrupt, failed fixup
	$RecordSize = Dec(_SwapEndian(StringMid($record,51,8)),2)
	$AttributeOffset = (Dec(StringMid($record,43,2))*2)+3
	While 1		;only want Attribute List and Data Attributes
		$Type = Dec(_SwapEndian(StringMid($record,$AttributeOffset,8)),2)
		If $Type > 256 Then ExitLoop		;attributes may not be in numerical order
		$AttributeSize = Dec(_SwapEndian(StringMid($record,$AttributeOffset+8,8)),2)
		If $Type = 32 Then
			$AttrList = StringMid($record,$AttributeOffset,$AttributeSize*2)	;whole attribute
			$AttrList = _DecodeAttrList($FileRef, $AttrList)		;produces $AttrQ - extra record list
			If $AttrList = "" Then
				_DebugOut($FileRef & " Bad Attribute List signature", $record)
				Return ""
			Else
				If $AttrQ[0] = "" Then ContinueLoop		;no new records
				$str = ""
				For $i = 1 To $AttrQ[0]
					ConsoleWrite("$AttrQ[$i]: " & $AttrQ[$i] & @CRLF)
					If Not IsNumber($FileTree[$AttrQ[$i]]) Then
						_DebugOut($FileRef & " Overwritten extra record (" & $AttrQ[$i] & ")", $record)
						Return ""
					EndIf
					$rec = _GetAttrListMFTRecord($FileTree[$AttrQ[$i]])
					If StringMid($rec,3,8) <> $RecordSignature Then
						_DebugOut($FileRef & " Bad signature for extra record", $record)
						Return ""
					EndIf
					If Dec(_SwapEndian(StringMid($rec,67,8)),2) <> $FileRef Then
						_DebugOut($FileRef & " Bad extra record", $record)
						Return ""
					EndIf
					$rec = _StripMftRecord($rec, $FileRef)
					If $rec = "" Then
						_DebugOut($FileRef & " Extra record failed Fixup", $record)
						Return ""
					EndIf
					$str &= $rec		;no header or end marker
				Next
				$record = StringMid($record,1,($RecordSize-8)*2+2) & $str & "FFFFFFFF"       ;strip end first then add
			EndIf
		ElseIf $Type = 128 Then
			ReDim $DataQ[UBound($DataQ) + 1]
			$DataQ[UBound($DataQ) - 1] = StringMid($record,$AttributeOffset,$AttributeSize*2) 		;whole data attribute
		EndIf
		$AttributeOffset += $AttributeSize*2
	WEnd
	Return $record
EndFunc

Func _DoFixup($record, $FileRef)		;handles NT and XP style
	$UpdSeqArrOffset = Dec(_SwapEndian(StringMid($record,11,4)))
	$UpdSeqArrSize = Dec(_SwapEndian(StringMid($record,15,4)))
	$UpdSeqArr = StringMid($record,3+($UpdSeqArrOffset*2),$UpdSeqArrSize*2*2)
	If $MFT_Record_Size = 1024 Then
		$UpdSeqArrPart0 = StringMid($UpdSeqArr,1,4)
		$UpdSeqArrPart1 = StringMid($UpdSeqArr,5,4)
		$UpdSeqArrPart2 = StringMid($UpdSeqArr,9,4)
		$RecordEnd1 = StringMid($record,1023,4)
		$RecordEnd2 = StringMid($record,2047,4)
		If $UpdSeqArrPart0 <> $RecordEnd1 OR $UpdSeqArrPart0 <> $RecordEnd2 Then
			_DebugOut($FileRef & " The record failed Fixup", $record)
			Return ""
		EndIf
		Return StringMid($record,1,1022) & $UpdSeqArrPart1 & StringMid($record,1027,1020) & $UpdSeqArrPart2
	ElseIf $MFT_Record_Size = 4096 Then
		$UpdSeqArrPart0 = StringMid($UpdSeqArr,1,4)
		$UpdSeqArrPart1 = StringMid($UpdSeqArr,5,4)
		$UpdSeqArrPart2 = StringMid($UpdSeqArr,9,4)
		$UpdSeqArrPart3 = StringMid($UpdSeqArr,13,4)
		$UpdSeqArrPart4 = StringMid($UpdSeqArr,17,4)
		$UpdSeqArrPart5 = StringMid($UpdSeqArr,21,4)
		$UpdSeqArrPart6 = StringMid($UpdSeqArr,25,4)
		$UpdSeqArrPart7 = StringMid($UpdSeqArr,29,4)
		$UpdSeqArrPart8 = StringMid($UpdSeqArr,33,4)
		$RecordEnd1 = StringMid($record,1023,4)
		$RecordEnd2 = StringMid($record,2047,4)
		$RecordEnd3 = StringMid($record,3071,4)
		$RecordEnd4 = StringMid($record,4095,4)
		$RecordEnd5 = StringMid($record,5119,4)
		$RecordEnd6 = StringMid($record,6143,4)
		$RecordEnd7 = StringMid($record,7167,4)
		$RecordEnd8 = StringMid($record,8191,4)
		If $UpdSeqArrPart0 <> $RecordEnd1 OR $UpdSeqArrPart0 <> $RecordEnd2 OR $UpdSeqArrPart0 <> $RecordEnd3 OR $UpdSeqArrPart0 <> $RecordEnd4 OR $UpdSeqArrPart0 <> $RecordEnd5 OR $UpdSeqArrPart0 <> $RecordEnd6 OR $UpdSeqArrPart0 <> $RecordEnd7 OR $UpdSeqArrPart0 <> $RecordEnd8 Then
			_DebugOut($FileRef & " The record failed Fixup", $record)
			Return ""
		Else
			Return StringMid($record,1,1022) & $UpdSeqArrPart1 & StringMid($record,1027,1020) & $UpdSeqArrPart2 & StringMid($record,2051,1020) & $UpdSeqArrPart3 & StringMid($record,3075,1020) & $UpdSeqArrPart4 & StringMid($record,4099,1020) & $UpdSeqArrPart5 & StringMid($record,5123,1020) & $UpdSeqArrPart6 & StringMid($record,6147,1020) & $UpdSeqArrPart7 & StringMid($record,7171,1020) & $UpdSeqArrPart8
		EndIf
	EndIf
EndFunc

Func _GetAttrListMFTRecord($Pos)
   Local $nBytes
   _WinAPI_SetFilePointerEx($hDisk, $ImageOffset+$Pos, $FILE_BEGIN)
   _WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
   $record = DllStructGetData($rBuffer, 1)
   Return $record		;returns MFT record for file
EndFunc

Func _ReadMFT()
   Local $nBytes
   _WinAPI_SetFilePointerEx($hDisk, $ImageOffset + $MFT_Offset)
   _WinAPI_ReadFile($hDisk, DllStructGetPtr($rBuffer), $MFT_Record_Size, $nBytes)
   $record = DllStructGetData($rBuffer, 1)
   If StringMid($record,3,8) = $RecordSignature And StringMid($record,47,4) = "0100" Then Return $record		;returns record for MFT
   _DebugOut("Check record for $MFT", $record)	;bad $MFT record
   Return ""
EndFunc

Func _GetDiskConstants()
	Local $nbytes
	$tBuffer = DllStructCreate("byte[512]")
	$read = _WinAPI_ReadFile($hDisk, DllStructGetPtr($tBuffer), 512, $nBytes)
	If $read = 0 Then Return ""
	$record = DllStructGetData($tBuffer, 1)
	$BytesPerSector = Dec(_SwapEndian(StringMid($record,25,4)),2)
	$SectorsPerCluster = Dec(_SwapEndian(StringMid($record,29,2)),2)
	$BytesPerCluster = $BytesPerSector * $SectorsPerCluster
	$LogicalClusterNumberforthefileMFT = Dec(_SwapEndian(StringMid($record,99,8)),2)
	$MFT_Offset = $BytesPerCluster * $LogicalClusterNumberforthefileMFT
	$ClustersPerFileRecordSegment = Dec(_SwapEndian(StringMid($record,131,8)),2)
	If $ClustersPerFileRecordSegment > 127 Then
		$MFT_Record_Size = 2 ^ (256 - $ClustersPerFileRecordSegment)
	Else
		$MFT_Record_Size = $BytesPerCluster * $ClustersPerFileRecordSegment
	EndIf
	$SectorsPerMftRecord = $MFT_Record_Size/$BytesPerSector
	_DebugOut("LogicalClusterNumberforthefileMFT: " & $LogicalClusterNumberforthefileMFT)
	_DebugOut("BytesPerCluster: " & $BytesPerCluster)
	_DebugOut("MFT_Record_Size: " & $MFT_Record_Size)
	Return $record
EndFunc

Func _DisplayInfo($DebugInfo)
   GUICtrlSetData($myctredit, $DebugInfo, 1)
EndFunc

Func _GetMountedDrivesInfo()
   GUICtrlSetData($Combo,"","")
   Local $menu = '', $Drive = DriveGetDrive('All')
   If @error Then
	  _DisplayInfo("Error - something went wrong in Func _GetPhysicalDriveInfo" & @CRLF)
	  Return
   EndIf
   For $i = 1 to $Drive[0]
	  $DriveType = DriveGetType($Drive[$i])
	  $DriveCapacity = Round(DriveSpaceTotal($Drive[$i]),0)
	  If DriveGetFileSystem($Drive[$i]) = 'NTFS' Then
		 $menu &=  StringUpper($Drive[$i]) & "  (" & $DriveType & ")  - " & $DriveCapacity & " MB  - NTFS|"
	  EndIf
   Next
   If $menu Then
	  _DisplayInfo("NTFS drives detected" & @CRLF)
	  GUICtrlSetData($Combo, $menu, StringMid($menu, 1, StringInStr($menu, "|") -1))
	  $IsImage = False
   Else
	  _DisplayInfo("No NTFS drives detected" & @CRLF)
   EndIf

   $j = Asc("z")
   For $i = $Drive[0] To 1 Step -1
	  If $Drive[$i] <> Chr($j) & ":" Then ExitLoop
	  $j -= 1
   Next
   $subst = Chr($j) & ":"
   _DisplayInfo("Substitute drive is " & StringUpper($subst) & @CRLF)
EndFunc

Func _DecToLittleEndian($DecimalInput)
   Return _SwapEndian(Hex($DecimalInput,8))
EndFunc

Func _SwapEndian($iHex)
   Return StringMid(Binary(Dec($iHex,2)),3, StringLen($iHex))
EndFunc

Func _UnicodeHexToStr($FileName)
   $str = ""
   For $i = 1 To StringLen($FileName) Step 4
	  $str &= ChrW(Dec(_SwapEndian(StringMid($FileName, $i, 4))))
   Next
   Return $str
EndFunc

Func _DebugOut($text, $var="")
   If $var Then $var = _HexEncode($var) & @CRLF
   $text &= @CRLF & $var
   ConsoleWrite($text)
   If $logfile Then FileWrite($logfile, $text)
EndFunc

Func _ExtractResidentFile($Name, $Size, $record)
	Local $nBytes
	$xBuffer = DllStructCreate("byte[" & $Size & "]")
    DllStructSetData($xBuffer, 1, '0x' & $DataRun)
    $zflag = 0
	Do
        DirCreate(StringMid($Name, 1, StringInStr($Name,"\",0,-1)))
		$hFile = _WinAPI_CreateFile($Name,3,6,7)
        If $hFile Then
            _WinAPI_SetFilePointer($hFile, 0,$FILE_BEGIN)
            _WinAPI_WriteFile($hFile, DllStructGetPtr($xBuffer), $Size, $nBytes)
            _WinAPI_CloseHandle($hFile)
            If StringInStr($Name, $subst) Then $ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
            Return
        Else
            If $zflag = 0 Then		;first pass
			   $mid = Int(StringLen($Name)/2)
			   $zPath = StringMid($Name, 1, StringInStr($Name, "\", 0, -1, $mid)-1)
			ElseIf $zflag = 1 Then		;second pass
			   $ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
			   $Name = StringReplace($Name,$subst, $zPath)	;restore full name
			   $zPath = StringMid($Name, 1, StringInStr($Name, "\", 0, 1, $mid)-1)
			Else		;fail
			   _DebugOut("Error in creating resident file " & StringReplace($Name,$subst,$zPath), $record)
			   $ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
			   Return
			EndIf
			$ret = _WinAPI_DefineDosDevice($subst, 0, $zPath)     ;open spare
			$Name = StringReplace($Name,$zPath, $subst)
			$zflag += 1
		 EndIf
    Until $hFile
EndFunc

Func _ExtractFile($record)
    $cBuffer = DllStructCreate("byte[" & $BytesPerCluster * 16 & "]")
    $zflag = 0
	Do
        DirCreate(StringMid($ADS_Name, 1, StringInStr($ADS_Name,"\",0,-1)))
		$hFile = _WinAPI_CreateFile($ADS_Name,3,6,7)
        If $hFile Then
            Select
                Case UBound($RUN_VCN) = 1		;no data, do nothing
                Case UBound($RUN_VCN) = 2 	;may be normal or sparse
                    If $RUN_VCN[1] = 0 And $IsSparse Then		;sparse
                        $FileSize = _DoSparse(1, $hFile, $DATA_InitSize)
                    Else								;normal
                        $FileSize = _DoNormal(1, $hFile, $cBuffer, $DATA_InitSize)
					EndIf
			    Case Else					;may be compressed
                    _DoCompressed($hFile, $cBuffer, $record)
			EndSelect
			If $DATA_RealSize > $DATA_InitSize Then
			    $FileSize = _WriteZeros($hfile, $DATA_RealSize - $DATA_InitSize)
			EndIf
            _WinAPI_CloseHandle($hFile)
            If StringInStr($ADS_Name, $subst) Then $ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
            Return
        Else
            If $zflag = 0 Then		;first pass
			   $mid = Int(StringLen($ADS_Name)/2)
			   $zPath = StringMid($ADS_Name, 1, StringInStr($ADS_Name, "\", 0, -1, $mid)-1)
			ElseIf $zflag = 1 Then		;second pass
			   $ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
			   $ADS_Name = StringReplace($ADS_Name,$subst, $zPath)	;restore full name
			   $zPath = StringMid($ADS_Name, 1, StringInStr($ADS_Name, "\", 0, 1, $mid)-1)
			Else		;fail
			   _DebugOut("Error in creating non-resident file " & StringReplace($ADS_Name,$subst,$zPath), $record)
			   $ret = _WinAPI_DefineDosDevice($subst, 2, $zPath)     ;close spare
			   Return
			EndIf
			$ret = _WinAPI_DefineDosDevice($subst, 0, $zPath)     ;open spare
			$ADS_Name = StringReplace($ADS_Name,$zPath, $subst)
			$zflag += 1
		 EndIf
    Until $hFile
 EndFunc

Func _WriteZeros($hfile, $count)
   Local $nBytes
   If Not IsDllStruct($sBuffer) Then _CreateSparseBuffer()
   While $count > $BytesPerCluster * 16
	  _WinAPI_WriteFile($hFile, DllStructGetPtr($sBuffer), $BytesPerCluster * 16, $nBytes)
	  $count -= $BytesPerCluster * 16
	  $ProgressSize = $DATA_RealSize - $count
   WEnd
   If $count <> 0 Then _WinAPI_WriteFile($hFile, DllStructGetPtr($sBuffer), $count, $nBytes)
   $ProgressSize = $DATA_RealSize
   Return 0
EndFunc

Func _DoCompressed($hFile, $cBuffer, $record)
   Local $nBytes
   $r=1
   $FileSize = $DATA_InitSize
   $ProgressSize = $FileSize
   Do
	  _WinAPI_SetFilePointerEx($hDisk, $ImageOffset+$RUN_VCN[$r]*$BytesPerCluster, $FILE_BEGIN)
	  $i = $RUN_Clusters[$r]
	  If (($RUN_VCN[$r+1]=0) And ($i+$RUN_Clusters[$r+1]=16) And $IsCompressed) Then
		 _WinAPI_ReadFile($hDisk, DllStructGetPtr($cBuffer), $BytesPerCluster * $i, $nBytes)
		 $Decompressed = _LZNTDecompress($cBuffer, $BytesPerCluster * $i)
		 If IsString($Decompressed) Then
			If $r = 1 Then
			   _DebugOut("Decompression error for " & $ADS_Name, $record)
			Else
			   _DebugOut("Decompression error (partial write) for " & $ADS_Name, $record)
			EndIf
			Return
		 Else		;$Decompressed is an array
			Local $dBuffer = DllStructCreate("byte[" & $Decompressed[1] & "]")
			DllStructSetData($dBuffer, 1, $Decompressed[0])
		 EndIf
		 If $FileSize > $Decompressed[1] Then
			_WinAPI_WriteFile($hFile, DllStructGetPtr($dBuffer), $Decompressed[1], $nBytes)
			$FileSize -= $Decompressed[1]
			$ProgressSize = $FileSize
		 Else
			_WinAPI_WriteFile($hFile, DllStructGetPtr($dBuffer), $FileSize, $nBytes)
		 EndIf
		 $r += 1
	  ElseIf $RUN_VCN[$r]=0 Then
		 $FileSize = _DoSparse($r, $hFile, $FileSize)
		 $ProgressSize = 0
	  Else
		 $FileSize = _DoNormal($r, $hFile, $cBuffer, $FileSize)
		 $ProgressSize = 0
	  EndIf
	  $r += 1
   Until $r > UBound($RUN_VCN)-2
   If $r = UBound($RUN_VCN)-1 Then
	  If $RUN_VCN[$r]=0 Then
		 $FileSize = _DoSparse($r, $hFile, $FileSize)
		 $ProgressSize = 0
	  Else
		 $FileSize = _DoNormal($r, $hFile, $cBuffer, $FileSize)
		 $ProgressSize = 0
	  EndIf
   EndIf
EndFunc

Func _DoNormal($r, $hFile, $cBuffer, $FileSize)
   Local $nBytes
   _WinAPI_SetFilePointerEx($hDisk, $ImageOffset+$RUN_VCN[$r]*$BytesPerCluster, $FILE_BEGIN)
   $i = $RUN_Clusters[$r]
   While $i > 16 And $FileSize > $BytesPerCluster * 16
	  _WinAPI_ReadFile($hDisk, DllStructGetPtr($cBuffer), $BytesPerCluster * 16, $nBytes)
	  _WinAPI_WriteFile($hFile, DllStructGetPtr($cBuffer), $BytesPerCluster * 16, $nBytes)
	  $i -= 16
	  $FileSize -= $BytesPerCluster * 16
	  $ProgressSize = $FileSize
   WEnd
   If $i = 0 Or $FileSize = 0 Then Return $FileSize
   If $i > 16 Then $i = 16
   _WinAPI_ReadFile($hDisk, DllStructGetPtr($cBuffer), $BytesPerCluster * $i, $nBytes)
   If $FileSize > $BytesPerCluster * $i Then
	  _WinAPI_WriteFile($hFile, DllStructGetPtr($cBuffer), $BytesPerCluster * $i, $nBytes)
	  $FileSize -= $BytesPerCluster * $i
	  $ProgressSize = $FileSize
	  Return $FileSize
   Else
	  _WinAPI_WriteFile($hFile, DllStructGetPtr($cBuffer), $FileSize, $nBytes)
	  $ProgressSize = 0
	  Return 0
   EndIf
EndFunc

Func _DoSparse($r,$hFile,$FileSize)
   Local $nBytes
   If Not IsDllStruct($sBuffer) Then _CreateSparseBuffer()
   $i = $RUN_Clusters[$r]
   While $i > 16 And $FileSize > $BytesPerCluster * 16
	 _WinAPI_WriteFile($hFile, DllStructGetPtr($sBuffer), $BytesPerCluster * 16, $nBytes)
	 $i -= 16
	 $FileSize -= $BytesPerCluster * 16
	 $ProgressSize = $FileSize
   WEnd
   If $i <> 0 Then
 	 If $FileSize > $BytesPerCluster * $i Then
		_WinAPI_WriteFile($hFile, DllStructGetPtr($sBuffer), $BytesPerCluster * $i, $nBytes)
		$FileSize -= $BytesPerCluster * $i
		$ProgressSize = $FileSize
	 Else
		_WinAPI_WriteFile($hFile, DllStructGetPtr($sBuffer), $FileSize, $nBytes)
		$ProgressSize = 0
		Return 0
	 EndIf
   EndIf
   Return $FileSize
EndFunc

Func _CreateSparseBuffer()
   Global $sBuffer = DllStructCreate("byte[" & $BytesPerCluster * 16 & "]")
   For $i = 1 To $BytesPerCluster * 16
	  DllStructSetData ($sBuffer, $i, 0)
   Next
EndFunc

Func _DoReparsePoints()
   local $RPs[1], $link, $target, $perm [1][4]
   $perm[0][0]="Everyone"
   $perm[0][1]=0	;deny
   $perm[0][2]=$FILE_LIST_DIRECTORY
   $perm[0][3]=$INHERIT_NO_PROPAGATE
   $RPs = StringSplit($Reparse, "*?")
   _DebugOut("Reparse Data (" & Int($RPs[0]/3) & " points)")
   For $i = 1 To $RPs[0]-2 Step 3
	  $link = $FileTree[$RPs[$i]]
	  $target = $outputpath & "\" & StringReplace($RPs[$i+2], ":", "")
	  If StringRight($target,1) = "\" Then $target = StringTrimRight($target,1)
	  If FileExists($target) Then
		 DirRemove($link)		;remove folder first
		 If $RPs[$i+1] = "0C0000A0" Then
			_WinAPI_CreateSymbolicLink($link, $target, 1)
		 Else
			_CreateJunctionPoint($link, $target)
		 EndIf
		 If @error Then
			_DebugOut("MFT Ref No = " & $RPs[$i] & @CRLF & _
			"Junction Path = " & $FileTree[$RPs[$i]] & @CRLF & _
			"Absolute Path = " & $RPs[$i+2] & @CRLF)
		 EndIf
		 If $target = StringMid($link,1,StringInStr($link,"\",0,-1)-1) Then _EditObjectPermissions($link,$perm)	;trap circles
	  EndIf
   Next
EndFunc

Func _CreateJunctionPoint($Link, $Target)
   Local $SubstituteName = "\??\" & $Target & Chr(0)		;nb null terminated - not essential
   Local $PrintName = $Target & Chr(0)					;nb null terminated - not essential
   Local $PathBuffer = $SubstituteName & $PrintName
   Local $PathBufferSize = StringLen($PathBuffer)
   Local $ReparseTag = 0xA0000003

   Local $InBuff = DllStructCreate("ulong ReparseTag;word ReparseDataLength;word Reserved;word SubstituteNameOffset;word SubstituteNameLength;word PrintNameOffset;word PrintNameLength;wchar PathBuffer["&$PathBufferSize&"]")
   DllStructSetData($InBuff,"ReparseTag",$ReparseTag)
   DllStructSetData($InBuff,"ReparseDataLength",$PathBufferSize*2 + 8)
   DllStructSetData($InBuff,"SubstituteNameOffset",0)
   DllStructSetData($InBuff,"SubstituteNameLength",StringLen($SubstituteName)*2 - 2)	;null not counted
   DllStructSetData($InBuff,"PrintNameOffset",StringLen($SubstituteName)*2)
   DllStructSetData($InBuff,"PrintNameLength",StringLen($PrintName)*2 -2)		;null not counted
   DllStructSetData($InBuff,"PathBuffer",$PathBuffer)

   ;Create a directory and apply reparse point on it
   DirCreate($Link)
   Local $hFile = _WinAPI_CreateFileEx('\\.\' & $Link, $OPEN_ALWAYS, BitOR($GENERIC_EXECUTE,$GENERIC_READ,$GENERIC_WRITE), $FILE_SHARE_READ, BitOR($FILE_OPEN_REPARSE_POINT,$FILE_FLAG_BACKUP_SEMANTICS))
	If Not $hFile Then
		 _DebugOut("Error in _WinAPI_CreateFileEx: " & _WinAPI_GetLastErrorMessage(), $Link & " -> " & $Target)
		 Return SetError(1, 0, 0)
	EndIf
	Local $Ret = DllCall('kernel32.dll', 'int', 'DeviceIoControl', 'ptr', $hFile, 'dword', $FSCTL_SET_REPARSE_POINT, 'ptr', DllStructGetPtr($InBuff), "ulong", DllStructGetSize($InBuff), 'ptr', 0, "ulong", 0, 'dword*', 0, 'ptr', 0)
	If (@error) Or (Not $Ret[0]) Then
		_DebugOut("Error in DeviceIoControl: " & _WinAPI_GetLastErrorMessage(), $Link & " -> " & $Target)
		_WinAPI_CloseHandle($hFile)
		Return SetError(3, 0, 0)
	 EndIf
	 _WinAPI_CloseHandle($hFile)
   If @error Then
	  DirRemove($Link)
   EndIf
EndFunc

Func _HexEncode($bInput)
   Local $tInput = DllStructCreate("byte[" & BinaryLen($bInput) & "]")
   DllStructSetData($tInput, 1, $bInput)
   Local $a_iCall = DllCall("crypt32.dll", "int", "CryptBinaryToString", _
	  "ptr", DllStructGetPtr($tInput), _
	  "dword", DllStructGetSize($tInput), _
	  "dword", 11, _
	  "ptr", 0, _
	  "dword*", 0)

   If @error Or Not $a_iCall[0] Then
	  Return SetError(1, 0, "")
   EndIf
   Local $iSize = $a_iCall[5]
   Local $tOut = DllStructCreate("char[" & $iSize & "]")
   $a_iCall = DllCall("crypt32.dll", "int", "CryptBinaryToString", _
	  "ptr", DllStructGetPtr($tInput), _
	  "dword", DllStructGetSize($tInput), _
	  "dword", 11, _
	  "ptr", DllStructGetPtr($tOut), _
	  "dword*", $iSize)

   If @error Or Not $a_iCall[0] Then
	  Return SetError(2, 0, "")
   EndIf

   Return SetError(0, 0, DllStructGetData($tOut, 1))
EndFunc

Func _LZNTDecompress($tInput, $Size)	;note function returns a null string if error, or an array if no error
	Local $tOutput[2]
	Local $cBuffer = DllStructCreate("byte[" & $BytesPerCluster*16 & "]")
    Local $a_Call = DllCall("ntdll.dll", "int", "RtlDecompressBuffer", _
            "ushort", 2, _
            "ptr", DllStructGetPtr($cBuffer), _
            "dword", DllStructGetSize($cBuffer), _
            "ptr", DllStructGetPtr($tInput), _
            "dword", $Size, _
            "dword*", 0)

    If @error Or $a_Call[0] Then	;if $a_Call[0]=0 then output size is in $a_Call[6], otherwise $a_Call[6] is invalid
        Return SetError(1, 0, "") ; error decompressing
    EndIf
    Local $Decompressed = DllStructCreate("byte[" & $a_Call[6] & "]", DllStructGetPtr($cBuffer))
	$tOutput[0] = DllStructGetData($Decompressed, 1)
	$tOutput[1] = $a_Call[6]
    Return SetError(0, 0, $tOutput)
EndFunc

Func _DoFileTreeProgress()
    GUICtrlSetData($ProgressStatus, "Examining MFT record " & $CurrentProgress & " of " & $Total & " (step 1 of 3)")
    GUICtrlSetData($ElapsedTime, "Elapsed time = " & _WinAPI_StrFromTimeInterval(TimerDiff($begin)))
	GUICtrlSetData($OverallProgress, 100 * $CurrentProgress / $Total)
EndFunc

Func _FolderStrucProgress()
	GUICtrlSetData($ProgressStatus, "Creating folder " & $CurrentProgress & " of " & $Total & " (step 2 of 3)")
	GUICtrlSetData($ElapsedTime, "Elapsed time = " & _WinAPI_StrFromTimeInterval(TimerDiff($begin)))
    GUICtrlSetData($OverallProgress, 100 * $CurrentProgress / $Total)
EndFunc

Func _ExtractionProgress()
	GUICtrlSetData($ProgressStatus, "Extracting record " & $CurrentProgress & " of " & $Total & " (step 3 of 3)")
	GUICtrlSetData($ElapsedTime, "Elapsed time = " & _WinAPI_StrFromTimeInterval(TimerDiff($begin)))
    GUICtrlSetData($OverallProgress, 100 * $CurrentProgress / $Total)
	GUICtrlSetData($ProgressFileName, $FN_FileName)
	GUICtrlSetData($FileProgress, 100 * ($DATA_RealSize - $ProgressSize) / $DATA_RealSize)
EndFunc

Func _ProcessImage()
	$TargetImageFile = FileOpenDialog("Select image file",@ScriptDir,"All (*.*)")
	If @error then Return
	$TargetImageFile = "\\.\"&$TargetImageFile
	_DisplayInfo("Selected disk image file: " & $TargetImageFile & @CRLF)
	GUICtrlSetData($Combo,"","")
	$Entries = ''
	_CheckMBR()
	GUICtrlSetData($Combo,$Entries,StringMid($Entries, 1, StringInStr($Entries, "|") -1))
	If $Entries = "" Then _DisplayInfo("Sorry, no NTFS volume found in that file." & @CRLF)
EndFunc   ;==>_ProcessImage

Func _CheckMBR()
	Local $nbytes, $PartitionNumber, $PartitionEntry,$FilesystemDescriptor
	Local $StartingSector,$NumberOfSectors
	Local $hImage = _WinAPI_CreateFile($TargetImageFile,2,2,7)
	$tBuffer = DllStructCreate("byte[512]")
	Local $read = _WinAPI_ReadFile($hImage, DllStructGetPtr($tBuffer), 512, $nBytes)
	If $read = 0 Then Return ""
	Local $sector = DllStructGetData($tBuffer, 1)
	For $PartitionNumber = 0 To 3
		$PartitionEntry = StringMid($sector,($PartitionNumber*32)+3+892,32)
		If $PartitionEntry = "00000000000000000000000000000000" Then ExitLoop ; No more entries
		$FilesystemDescriptor = StringMid($PartitionEntry,9,2)
		$StartingSector = Dec(_SwapEndian(StringMid($PartitionEntry,17,8)),2)
		$NumberOfSectors = Dec(_SwapEndian(StringMid($PartitionEntry,25,8)),2)
		If ($FilesystemDescriptor = "EE" and $StartingSector = 1 and $NumberOfSectors = 4294967295) Then ; A typical dummy partition to prevent overwriting of GPT data, also known as "protective MBR"
			_CheckGPT($hImage)
		ElseIf $FilesystemDescriptor = "05" Or $FilesystemDescriptor = "0F" Then ;Extended partition
			_CheckExtendedPartition($StartingSector, $hImage)
		ElseIf $FilesystemDescriptor = "07" Then ;Marked as NTFS
			$Entries &= _GenComboDescription($StartingSector,$NumberOfSectors)
		EndIf
    Next
	If $Entries = "" Then ;Also check if pure partition image (without mbr)
		$NtfsVolumeSize = _TestNTFS($hImage, 0)
		If $NtfsVolumeSize Then $Entries = _GenComboDescription(0,$NtfsVolumeSize)
	EndIf
	_WinAPI_CloseHandle($hImage)
EndFunc   ;==>_CheckMBR

Func _CheckGPT($hImage) ; Assume GPT to be present at sector 1, which is not fool proof
   ;Actually it is. While LBA1 may not be at sector 1 on the disk, it will always be there in an image.
	Local $nbytes,$read,$sector,$GPTSignature,$StartLBA,$Processed=0,$FirstLBA,$LastLBA
	$tBuffer = DllStructCreate("byte[512]")
	$read = _WinAPI_ReadFile($hImage, DllStructGetPtr($tBuffer), 512, $nBytes)		;read second sector
	If $read = 0 Then Return ""
	$sector = DllStructGetData($tBuffer, 1)
	$GPTSignature = StringMid($sector,3,16)
	If $GPTSignature <> "4546492050415254" Then
		_DebugOut("Error: Could not find GPT signature:", StringMid($sector,3))
		Return
	EndIf
	$StartLBA = Dec(_SwapEndian(StringMid($sector,147,16)),2)
	$PartitionsInArray = Dec(_SwapEndian(StringMid($sector,163,8)),2)
	$PartitionEntrySize = Dec(_SwapEndian(StringMid($sector,171,8)),2)
	_WinAPI_SetFilePointerEx($hImage, $StartLBA*512, $FILE_BEGIN)
	$SizeNeeded = $PartitionsInArray*$PartitionEntrySize ;Set buffer size -> maximum number of partition entries that can fit in the array
	$tBuffer = DllStructCreate("byte[" & $SizeNeeded & "]")
	$read = _WinAPI_ReadFile($hImage, DllStructGetPtr($tBuffer), $SizeNeeded, $nBytes)
	If $read = 0 Then Return ""
	$sector = DllStructGetData($tBuffer, 1)
	Do
		$FirstLBA = Dec(_SwapEndian(StringMid($sector,67+($Processed*2),16)),2)
		$LastLBA = Dec(_SwapEndian(StringMid($sector,83+($Processed*2),16)),2)
		If $FirstLBA = 0 And $LastLBA = 0 Then ExitLoop ; No more entries
		$Processed += $PartitionEntrySize
		If Not _TestNTFS($hImage, $FirstLBA) Then ContinueLoop ;Continue the loop if filesystem not NTFS
		$Entries &= _GenComboDescription($FirstLBA,$LastLBA-$FirstLBA)
	Until $Processed >= $SizeNeeded
EndFunc   ;==>_CheckGPT

Func _CheckExtendedPartition($StartSector, $hImage)	;Extended partitions can only contain Logical Drives, but can be more than 4
   Local $nbytes,$read,$sector,$NextEntry=0,$StartingSector,$NumberOfSectors,$PartitionTable,$FilesystemDescriptor
   $tBuffer = DllStructCreate("byte[512]")
   While 1
	  _WinAPI_SetFilePointerEx($hImage, ($StartSector + $NextEntry) * 512, $FILE_BEGIN)
	  $read = _WinAPI_ReadFile($hImage, DllStructGetPtr($tBuffer), 512, $nBytes)
	  If $read = 0 Then Return ""
	  $sector = DllStructGetData($tBuffer, 1)
	  $PartitionTable = StringMid($sector,3+892,64)
	  $FilesystemDescriptor = StringMid($PartitionTable,9,2)
	  $StartingSector = $StartSector+$NextEntry+Dec(_SwapEndian(StringMid($PartitionTable,17,8)),2)
	  $NumberOfSectors = Dec(_SwapEndian(StringMid($PartitionTable,25,8)),2)
	  If $FilesystemDescriptor = "07" Then $Entries &= _GenComboDescription($StartingSector,$NumberOfSectors)
	  If StringMid($PartitionTable,33) = "00000000000000000000000000000000" Then ExitLoop ; No more entries
	  $NextEntry = Dec(_SwapEndian(StringMid($PartitionTable,49,8)),2)
   WEnd
EndFunc   ;==>_CheckExtendedPartition

Func _TestNTFS($hImage, $PartitionStartSector)
	Local $nbytes, $TotalSectors
	If $PartitionStartSector <> 0 Then
		_WinAPI_SetFilePointerEx($hImage, $PartitionStartSector*512, $FILE_BEGIN)
	Else
		_WinAPI_CloseHandle($hImage)
		$hImage = _WinAPI_CreateFile($TargetImageFile,2,2,7)
	EndIf
	$tBuffer = DllStructCreate("byte[512]")
	$read = _WinAPI_ReadFile($hImage, DllStructGetPtr($tBuffer), 512, $nBytes)
	If $read = 0 Then Return ""
	$sector = DllStructGetData($tBuffer, 1)
	$TestSig = StringMid($sector,9,8)
	$TotalSectors = Dec(_SwapEndian(StringMid($sector,83,8)),2)
	If $TestSig = "4E544653" Then Return $TotalSectors		; Volume is NTFS
	_DebugOut("Could not find NTFS:", $sector)		; Volume is not NTFS
    Return 0
EndFunc   ;==>_TestNTFS

Func _GenComboDescription($StartSector,$SectorNumber)
	Return "Offset = " & $StartSector*512 & ": Volume size = " & Round(($SectorNumber*512)/1024/1024/1024,2) & " GB|"
EndFunc   ;==>_GenComboDescription

Func _GetPhysicalDrives($InputDevice)
	Local $PhysicalDriveString, $hFile0
	If StringLeft($InputDevice,10) = "GLOBALROOT" Then ; Shadow copies starts at 1 whereas physical drive starts at 0
		$i=1
	Else
		$i=0
	EndIf
	GUICtrlSetData($Combo,"","")
	$Entries = ''
	GUICtrlSetData($ComboPhysicalDrives,"","")
	$sDrivePath = '\\.\'&$InputDevice
	ConsoleWrite("$sDrivePath: " & $sDrivePath & @CRLF)
	Do
		$hFile0 = _WinAPI_CreateFile($sDrivePath & $i,2,2,2)
		If $hFile0 <> 0 Then
			ConsoleWrite("Found: " & $sDrivePath & $i & @CRLF)
			_WinAPI_CloseHandle($hFile0)
			$PhysicalDriveString &= $sDrivePath&$i&"|"
		EndIf
		$i+=1
	Until $hFile0=0
	GUICtrlSetData($ComboPhysicalDrives, $PhysicalDriveString, StringMid($PhysicalDriveString, 1, StringInStr($PhysicalDriveString, "|") -1))
EndFunc

Func _TestPhysicalDrive()
	$TargetImageFile = GUICtrlRead($ComboPhysicalDrives)
	If @error then Return
	_DisplayInfo("Target is " & $TargetImageFile & @CRLF)
	GUICtrlSetData($Combo,"","")
	$Entries = ''
	_CheckMBR()
	GUICtrlSetData($Combo,$Entries,StringMid($Entries, 1, StringInStr($Entries, "|") -1))
	If $Entries = "" Then _DisplayInfo("Sorry, no NTFS volume found" & @CRLF)
	If StringInStr($TargetImageFile,"GLOBALROOT") Then
		$IsShadowCopy=True
		$IsPhysicalDrive=False
		$IsImage=False
	ElseIf StringInStr($TargetImageFile,"PhysicalDrive") Then
		$IsShadowCopy=False
		$IsPhysicalDrive=True
		$IsImage=False
	EndIf
EndFunc

Func _GetRunsFromAttributeListMFT0()
	For $i = 1 To UBound($DataQ) - 1
		_DecodeDataQEntry($DataQ[$i])
		If $NonResidentFlag = '00' Then
;			ConsoleWrite("Resident" & @CRLF)
		Else
			Global $RUN_VCN[1], $RUN_Clusters[1]
			$TotalClusters = $Data_Clusters
			$RealSize = $DATA_RealSize		;preserve file sizes
			If Not $InitState Then $DATA_InitSize = $DATA_RealSize
			$InitSize = $DATA_InitSize
			_ExtractDataRuns()
			If $TotalClusters * $BytesPerCluster >= $RealSize Then
;				_ExtractFile($MFTRecord)
			Else 		 ;code to handle attribute list
				$Flag = $IsCompressed		;preserve compression state
				For $j = $i + 1 To UBound($DataQ) -1
					_DecodeDataQEntry($DataQ[$j])
					$TotalClusters += $Data_Clusters
					_ExtractDataRuns()
					If $TotalClusters * $BytesPerCluster >= $RealSize Then
						$DATA_RealSize = $RealSize		;restore file sizes
						$DATA_InitSize = $InitSize
						$IsCompressed = $Flag		;recover compression state
						ExitLoop
					EndIf
				Next
				$i = $j
			EndIf
		EndIf
	Next
EndFunc