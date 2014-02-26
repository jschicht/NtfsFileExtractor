Description

This tool will extract files from an NTFS volume. It supports resident, non-resident, compressed, sparse, normal, alternate data streams (ADS). It has several different methods/modes to choose from. In short the choices are: 
 -Mounted volume, image file, direct access to \\.\PhysicalDriveN, detect and access shadow copies 
 -Active files, deleted files, or all files. 
 -Choose individual files based on their index number. 


At program start all mounted NTFS volumes are populated in the second combobox at the top. You can also rescan for volumes by pressing the button 'Rescan Mounted Drives'. 

To scan \\.\PhysicalDrive for attached disks press the button "Scan Physical". The detected drives will be visible in the first combo at the top. Select a drive and press the button "Test it". The detected NTFS volumes on the drive will be displayed in the second combo. Select what files to extract and press "Start Extraction" to start extracting the files. 

To scan for shadow copies press the button "Scan Shadows". The detected shadow copies will be visible in the first combo at the top. Select a shadow copy and press the button "Test it" to get detected NTFS volumes. The result is displayed in the second combo. Select what files to extract and press "Start Extraction" to start extracting the files. 

By default the output directory is set to the directory the program is executed from. In order to set it differently, press the button 'Choose Output'. 

Selecting the target volume is done by choosing the right one in the combobox. When using image file, the detected volumes in the image are populated into the combobox, where you can choose the right one. The support for image files are for disk and partition images. For disk images both MBR and GPT style are supported. 

When choosing which files to extract from target volume, choose right selection on the left side from: 
 -All (both active and deleted) 
 -Deleted (only deleted files) 
 -Active (only active files) 
 -User Select (choose files to extract based on their index number) 


The 'User Select' mode will fire up an input box after you have pressed 'Start Extraction'. In there you can put a comma separated list of the index numbers you want to have extracted. For instance if you want to extract $MFT and $LogFile you will enter '0,2' which are their respective index numbers. 

Extracted Alternate Data Streams (ADS) will be outputted in the format: 
 -basefile.ext[ADS_adsname.ext] 


Extracted files that have been deleted are outputted in the format: 
 -[DEL+IndexNumber]FileName.ext 


Because of this prefix of deleted files, there is a possibility of running into file paths that are too long to make your filesystem happy. This possible issue will only be relevant if extracting deleted files that was stored inside a deep path where the whole path have been deleted. This prefix is necessary though to differentiate deleted from active files. 

Reparse points and hardlinks are extracted as they are, which means they will have the correct type set, but the link will always point to the extracted target, and not the original target. 

Since this tool extract directly off physical disk, it will effectively bypass any file access restriction/security otherwise imposed by the filesystem. For instance the SAM or SYSTEM hive, or the pagefile can be extracted by using their index numbers. And obviously the same also goes for the NTFS systemfiles/metafiles which are not even visible in explorer. 

The extracted $MFT is perfect to feed into mft2csv, which will decode the file records and produce a csv with the information. 

The tools have been tested on almost all recent Windows version, from 32-bit XP to 64-bit Windows 8, and it works great.

ToDo
 -Optionally choose which attribute to extract. 

Thanks and credits
 -DDan at forensicfocus for being an enormous contributor both with code and advice. 
 AutoIt forums (KaFu & trancexxx) where the starter code was provided; http://www.autoitscript.com/forum/topic/94269-mft-access-reading-parsing-the-master-file-table-on-ntfs-filesystems/ 

