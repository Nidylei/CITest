#!/bin/csh

#Note: This script is csh, not bash.
#      This script is only for FreeBSD10.0 or higher version.

set logFile=/root/autobuild.log       
set srcPath = /usr/devsrc
set buildworldFlag  =  "no"     #Do not build world by default 
set sourceCodeURL  =  "https://github.com/freebsd/freebsd.git"
set br = "master"
date > "/tmp/tempLogForAutoBuild.log"

#Provide help information 
if( $#argv >= 1 ) then
	if( "$argv[1]" == "-h" || "$argv[1]" == "--help" ) then
		echo "Usage:"
		echo "       ./autobuild.sh [--buildworld] [--srcURL <URL>] [-b <branch>] [--log <filename>]"
		echo " "
		echo "Parameters:"
		echo "           --buildworld: need to build world"
		echo "           --srcURL: source code URL"
		echo "           -b: git branch name"
		echo "           --log: log file name"
		echo " "
		echo "Example:"
		echo "         ./autobuild.sh -b dev --srcURL https://github.com/freebsd/freebsd.git --log /tmp/build.log"
		exit 0
	endif
endif

#Parse input parameters
@ i = 1
while( $i <= $#argv )
    if( "$argv[$i]" == "--srcURL" ) then
        @ i = $i + 1
        if( $i >  $#argv ) then
            echo "Error: Please specify a source code URL" | tee -a "/tmp/tempLogForAutoBuild.log"
            exit 1
        else
            set sourceCodeURL  = $argv[$i] 
        endif
    endif
	
	if( "$argv[$i]" == "--log" ) then
        @ i = $i + 1
        if( $i >  $#argv ) then
            echo "Error: Please give a log file name" | tee -a "/tmp/tempLogForAutoBuild.log"
            exit 1
        else
            set logFile  = $argv[$i] 
        endif
    endif
	
	if( "$argv[$i]" == "-b" ) then
        @ i = $i + 1
        if( $i >  $#argv ) then
            echo "Error: Please give a branch name" | tee -a "/tmp/tempLogForAutoBuild.log"
            exit 1
        else
            set br  = $argv[$i] 
        endif
    endif
	
	if( "$argv[$i]" == "--buildworld" ) then
	    set buildworldFlag  = "yes"
	endif
	
    @ i = $i + 1
end

cat /tmp/tempLogForAutoBuild.log > $logFile

#A directory to store the source code from URL
if( -e $srcPath ) then
    rm -rf $srcPath
endif
mkdir -p $srcPath

#Get the source code from the URL
echo "The branch is: $br"   >> $logFile
echo "The source code URL is: $sourceCodeURL"   >> $logFile
git clone -b $br $sourceCodeURL $srcPath --quiet
if( $? != 0 ) then
	echo "Error: git clone from $sourceCodeURL to $srcPath failed."  >> $logFile
	exit 1
endif 
date >> $logFile
echo "git clone from $sourceCodeURL to $srcPath successfully."  >> $logFile

cd  $srcPath
#Build world if necessary 
if( $buildworldFlag == "yes" ) then
    date >> $logFile
    echo "Begin to build world and it will take a very long time."  >> $logFile
    make -j4 buildworld
	if( $? != 0 ) then
	    echo "Error: Build world failed." >> $logFile
	    exit 1
    endif 
	echo "Build world successfully."  >> $logFile
	date >> $logFile
endif

#Build kernel  
echo "Begin to build kernel and it will take a long time."  >> $logFile
uname -p | grep "i386"
if( $? == 0 ) then
	echo "The processor is i386."     >> $logFile
	make -j4 buildkernel KERNCONF=GENERIC TARGET=i386 TARGET_ARCH=i386  
	if( $? != 0 ) then
	    echo "Error: Build kernel failed." >> $logFile
		exit  1
	endif
else
	echo "The processor is amd64."    >> $logFile 
	make -j4 buildkernel KERNCONF=GENERIC 
	if( $? != 0 ) then
	    echo "Error: Build kernel failed." >> $logFile
		exit  1
	endif
endif

echo "Build kernel successfully."  >> $logFile


#Install kernel
echo "Begin to install kernel and it will take a moment."  >> $logFile
make installkernel KERNCONF=GENERIC
if( $? != 0 ) then
	echo "Error: Install kernel failed."  >> $logFile
	exit 1
endif   
echo "Install kernel successfully."  >> $logFile

#Install world if necessary
if( $buildworldFlag == "yes" ) then
    echo "Begin to install world and it will take a moment."  >> $logFile
    make installworld 
    if( $? != 0 ) then
        echo "Error: Install world failed."  >> $logFile
        exit 1
    endif   
    echo "Install world successfully."  >> $logFile
endif

echo "To reboot VM after syncing, building and installing kernel/world."  >>  $logFile
date >> $logFile
sync
reboot



