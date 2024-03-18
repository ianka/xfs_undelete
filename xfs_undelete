#!/usr/bin/env tclsh
##
## Copyright (c) 2019 Jan Kandziora <jjj@gmx.de>
##
## This source code is licensed under the GNU General Public License,
## Version 3. See the file COPYING for more details.
##

## Load packages.
package require cmdline


##
## Defaults.
##


## Hard coded filetypes.
set filetypes {
	bin application/octet-stream  "Binary data"
	txt text/plain                "Plain Text"
}

## Default sector size. Is updated after reading the superblock.
set sectsize 512


## Set UTC timezone if the timezone cannot be detected.
if {[catch {clock scan "now"}]} {
		set env(TZ) ":UTC"
		puts stderr "Timezone cannot be detected. Defaulting to UTC."
}


##
## Compatibility functions.
##

## Define our own private lmap if it's not supplied by Tcl.
if {[catch {lmap var {} {}}]} {
	proc lmap {_vars list body} {
		foreach _var $_vars {
			upvar 1 $_var $_var
		}
		set res {}
		foreach $_vars $list {
			lappend res [uplevel 1 $body]
		}
		set res
	}
}

## Define our own private lsort -stride if it's not supplied by Tcl.
if {[catch {lsort -stride 2 {{} {}}}]} {
	rename lsort _lsort
	proc lsort {args} {
		## Isolate the value of the stride option, if any.
		set unsortedlist [lindex $args end]
		set options {}
		set stride 0
		foreach option [lrange $args 0 end-1] {
			if {$stride eq {}} {
				set stride $option
			} elseif {$option eq {-stride}} {
				set stride {}
			} else {
				lappend options $option
			}
		}

		## Check the new -stride option.
		if {$stride<2} {
			## No stride option. Sort list as given.
			_lsort {*}$options $unsortedlist
		} else {
			## Stride option. Rearrange the list into groups of -stride size.
			set groupedlist {}
			set group {}
			foreach element $unsortedlist {
				lappend group $element
				if {[llength $group]==$stride} {
					lappend groupedlist $group
					set group {}
				}
			}

			## Sort the groups, then flatten the result.
			concat {*}[_lsort {*}$options $groupedlist]
		}
	}
}


##
## Functions.
##

## Initialize mimetypes mappings.
set mimetypes [dict create]
foreach {extension mimetype name} $::filetypes {
	dict set mimetypes $mimetype $extension
}

## Guess extension from mimetype.
proc extension {mimetype} {
	## This hack is neccessary because most magic files found in the wild have
	## very poor support for file extensions. Mime type support is usually good.
	if {[dict exists $::mimetypes $mimetype]} {
		return [dict get $::mimetypes $mimetype]
	} elseif {[regexp {^.*?/([[:alnum:]]*[-.])?(.*?)(\+.*)?$} $mimetype match ldummy extension rdummy]} {
		return [string tolower $extension]
	} else {
		return "bin"
	}
}


## Check if the file type matches against a list of patterns.
proc matchFiletype {patterns mimetype extension} {
	## Run through all patterns.
	foreach pattern $patterns {
		## Check if extension or mimetype.
		if {[string match */* $pattern]} {
			## Mimetype.
			if {[string match $pattern $mimetype]} {
				return 1
			}
		} else {
			## Extension.
			if {[string match $pattern $extension]} {
				return 1
			}
		}
	}

	## No match.
	return 0
}


## Readlink helper.
proc readlink {symlink} {
	if {[catch {exec -- readlink -e $symlink} node]} {
		return
	}

	return $node
}


## Mountpoint helper.
proc mountpoint {dir} {
	## Get the mountpoint of the output directory.
	while {[catch {exec -- stat -L --format=%m $dir} result]} {
		## Try again with the parent directory if the path does not exist.
		set dir [file dirname $dir]
	}

	if {$result eq "?"} {
		puts stderr "Your  stat  utility does not support the %m format option."
		exit 32
	}

	return $result
}


## DD helper.
proc dd {args} {
	upvar inode restartinode

	## Setup C locale for parsing error messages
	set lang $::env(LANG)
	set ::env(LANG) C

	## Call dd with given options.
	if {[catch {exec -ignorestderr -- dd {*}$args 2>@1} err]} {
		## Evalulate error message.
		switch -glob -- [lindex [split $err \n] 0] {
			"*: No space left on device" {
				puts stderr [format $::offormat {}]
				puts stderr "To restart at this point, call the script with the option -s $restartinode"
				exit 32
			}
			default {
				## Reset locale.
				set ::env(LANG) $lang

				## Ignore the error and continue with next inode.
				return -code continue
			}
		}
	}

	## No error. Reset locale.
	set ::env(LANG) $lang
}


## Investigate inode block.
proc investigateInodeBlock {ag block} {
	## Calculate device block number.
	set dblock [expr {$::agblocks*$ag+$block}]

	## Read the block.
	seek $::fd [expr {$::blocksize*$dblock}]
	set data [read $::fd $::blocksize]

	## Run through all potential inodes in a block.
	for {set boffset 0} {$boffset<$::blocksize} {incr boffset $::inodesize} {
		## Skip if not the magic string of an inode record.
		if {[string range $data $boffset $boffset+1] ne "IN"} continue

		## Found. Get inode version.
		binary scan [string index $data $boffset+4] cu inode_version

		## Get inode number and extent offset.
		if {$inode_version>=3} {
			## Inode versions >=3 have their inode number stored in the inode block.
			binary scan [string range $data $boffset+152 $boffset+159] Wu inode

			## Extent records start from position 176 within the inode record.
			set inode_extent_offset 176
		} else {
			## Inode versions <3 have their inode number calculated from their position within the filesystem image.
			set inode [expr {($::blocksize*$dblock+$boffset)/$::inodesize}]

			## Extent records start from position 100 within the inode record.
			set inode_extent_offset 100
		}

		## Log each visited inode.
		puts -nonewline stderr [format [expr {$::passedstart?$::cmformat:$::skformat}] $inode [expr {100*$::ichecked/double($::icount)}]]
		incr ::ichecked

		## Check if this is the inode we should pass before starting recovery
		if {[dict get $::parameters s] eq $inode} {
			set ::passedstart 1
		}

		## Skip if we haven't passed the start inode yet.
		if {!$::passedstart} continue

		## Skip if this inode is in the list of inodes to ignore.
		if {$inode in [split [dict get $::parameters x] ,]} continue

		## Skip if not the magic string of an unused/deleted inode.
		if {[string range $data $boffset $boffset+3] ne "IN\0\0"} continue

		## Get ctime and mtime.
		binary scan [string range $data $boffset+48 $boffset+51] Iu ctime
		binary scan [string range $data $boffset+40 $boffset+43] Iu mtime

		## Ignore files deleted outside of the given time range.
		if {$ctime<[lindex $::ctimes 0] || $ctime>[lindex $::ctimes 1]} continue

		## Ignore files last modified outside of the given time range.
		if {$mtime<[lindex $::mtimes 0] || $mtime>[lindex $::mtimes 1]} continue

		## Get output filename.
		set of [file join [dict get $::parameters o] [format "%s_%s" [clock format $ctime -format "%Y-%m-%d-%H-%M"] $inode]]

		## Make a dict of any extents found.
		set extents [dict create]
		for {set ioffset $inode_extent_offset} {$ioffset+15<$::inodesize} {incr ioffset 16} {
			## Get extent.
			set extent [string range $data $boffset+$ioffset [expr {$boffset+$ioffset+15}]]

			## Ignore unused extents.
			if {$extent eq "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"} continue

			## Get data blocks from extent.
			binary scan $extent B* extbits

			## Ignore preallocated, unwritten extents.
			if {[string index $extbits 0]} continue

			## Get extent information.
			set loffset [expr 0b[string range $extbits 1 54]]
			set aag     [expr 0b[string range $extbits 55 106-$::agblklog]]
			set ablock  [expr 0b[string range $extbits 107-$::agblklog 106]]
			set count   [expr 0b[string range $extbits 107 127]]
			set skip    [expr {$aag*$::agblocks+$ablock}]

			## Silently ignore extents beyond the filesystem. These are clearly bogus.
			if {($skip+$count)>=$::dblocks} continue

			## Silently ignore extents even a 64-bit dd cannot handle. These are most likely bogus.
			if {($::blocksize*$loffset)>=(2**63-1)} continue

			## Set up extent record.
			dict set extents $loffset [dict create skip $skip count $count]
		}

		## Ignore all files without valid extents.
		if {$extents eq {}} continue

		## Ignore all files without any extent starting at loffset zero. These are most likely bogus.
		if {![dict exist $extents 0]} continue

		## Calculate the file size from the extents recovered.
		set filesize [::tcl::mathfunc::max {*}[lmap {loffset inf} $extents {
			expr {$::blocksize*($loffset+[dict get $inf count])}
		}]]

		## Ignore all files larger than the limit.
		if {$::maxsize ne {} && $filesize>$::maxsize} continue

		## Recover first block of loffset zero extent for file type reconstruction. Ignore file if dd reported a problem.
		dd if=$::fs of=$of bs=$::blocksize skip=[dict get $extents 0 skip] seek=0 count=1 conv=notrunc status=none

		## Reconstruct file extension from file content.
		if {![catch {exec -ignorestderr -- file --brief --mime-type $of {*}$::magicopts} mimetype]} {
			## No error. Guess extension from mimetype.
			set extension [extension $mimetype]

			## Rename the recovered file.
			set rof [format "%s.%s" $of $extension]
			file rename -force $of $rof
		} else {
			## Error. No extension.
			set extension {}

			## No renaming of the recovered file.
			set rof $of
		}

		## Ignore all files with extensions or mimetypes from the ignore list.
		if {[matchFiletype [split [dict get $::parameters i] ,] $mimetype $extension]} {
			file delete -force $rof
			continue
		}

		## Only recover those files with extensions or mimetypes from the recover list.
		if {![matchFiletype [split [dict get $::parameters r] ,] $mimetype $extension]} {
			file delete -force $rof
			continue
		}

		## Recover all extents.
		dict for {loffset inf} $extents {
			dict with inf {
				## Recover the data from this extent. Ignore extents for which dd reported a problem.
				dd if=$::fs of=$rof bs=$::blocksize skip=$skip seek=$loffset count=$count conv=notrunc status=none
			}
		}

		## Remove trailing zeroes for those files with extensions or mimetypes from the trailing zero list.
		if {[matchFiletype [split [dict get $::parameters z] ,] $mimetype $extension]} {
			## Open the the recovered file. No character set nor crlf translation.
			set rfd [open $rof r+]
			fconfigure $rfd -translation binary

			## Read last block and trim trailing zeroes.
			seek $rfd -$::blocksize end
			set lastblock [string trimright [read $rfd $::blocksize] \0]

			## Rewrite last block.
			seek $rfd -$::blocksize end
			puts -nonewline $rfd $lastblock
			chan truncate $rfd

			## Close recovered file.
			close $rfd
		}


		## Log.
		puts stderr [format $::rmformat $rof]
	}
}


## Traverse through inode tree.
proc traverseInodeTree {ag block} {
	## Read inode tree block.
	seek $::fd [expr {$::blocksize*($::agblocks*$ag+$block)}]
	set data [read $::fd $::blocksize]

	## Set record start index depending on inode btree magic.
	## Ignore any tree of unknown format.
	switch -- [string range $data 0 3] {
		IABT {set index 16}
		IAB3 {set index 56}
		default return
	}

	## Get level and number of records.
	binary scan [string range $data 4 5] Su bb_level
	binary scan [string range $data 6 7] Su bb_numrecs

	## Check if node or leaf.
	if {$bb_level>0} {
		## Node. Run through all pointer records.
		for {set rec 0 ; set index [expr {($::blocksize+$index)/2}]} {$rec<$bb_numrecs} {incr rec ; incr index 4} {
			## Get block number of branch.
			binary scan [string range $data $index $index+3] Iu agi_branch

			## Traverse through branch.
			traverseInodeTree $ag $agi_branch
		}
	} else {
		## Leaf. Run through all leaf records.
		for {set rec 0} {$rec<$bb_numrecs} {incr rec ; incr index 16} {
			## Get start inode number.
			binary scan [string range $data $index $index+3] Iu agi_start

			## Run through all inode records.
			for {set inode 0} {$inode<64} {incr inode $::inopblock} {
				## Get block number.
				set iblock [expr {($agi_start+$inode)/$::inopblock}]

				## Investigate that block for deleted inodes.
				investigateInodeBlock $ag $iblock
			}
		}
	}
}


## Parse a time range.
proc parseTimerange {timerange} {
	## Parse the different kinds of valid incomplete ranges.
	switch -regexp -matchvar match -- $timerange {
		{^$}             {set times [list "epoch" "now"]}
		{^\.\.$}         {set times [list "epoch" "now"]}
		{^\.\.(.+)$}     {set times [list "epoch" [lindex $match 1]]}
		{^(.+)\.\.$}     {set times [list [lindex $match 1] "now"]}
		{^(.+)\.\.(.+)$} {set times [lrange $match 1 2]}
		default          {set times [list $timerange "now"]}
	}

	## Convert symbolic times into seconds since epoch and return those values.
	lmap t $times {
		if {[catch {clock scan $t} t]} {
			puts stderr "Unable to parse time range. Please put it as a range of time specs Tcl's \[clock scan\] can understand, e.g. 2022-06-04..-2hours. A single value as -2hours is considered the same as a range -2hours..now."
			exit 32
		}
		set t
	}
}


##
## Main program.
##


## Set LANG environment variable if not set.
if {![info exists env(LANG)]} {
	set env(LANG) C
}


## Parse command line options.
if {[catch {set parameters [cmdline::getoptions argv {
	{t.arg ""              "deleted since"}
	{T.arg ""              "modified since"}
	{r.arg "*"             "list of file extensions and mimetypes to recover"}
	{i.arg "bin"           "list of file extensions and mimetypes to ignore"}
	{z.arg "text/*"        "list of file extensions and mimetypes to remove all trailing zeroes from"}
	{o.arg "xfs_undeleted" "target directory for recovered files"}
	{s.arg ""              "restart at inode number"}
	{S.arg ""              "ignore all files larger than this limit"}
	{x.arg ""              "list of inode numbers to ignore"}
	{m.arg ""              "magic path passed to the 'file' utility"}
	{l                     "list file extensions understood"}
	{no-remount-readonly   "do not remount read-only before recovery"}
} {[options] device -- options are:}]} result]} {
	puts stderr $result
	exit 127
}


## Set default pattern for the r parameter if empty.
if {[dict get $::parameters r] eq {}} {
	dict set ::parameters r *
}


## We passed the start inode already if there wasn't one set.
set passedstart [expr {[dict get $::parameters s] eq {}}]


## Pass magic path to file if specified
if {[dict get $::parameters m] ne {}} {
	set magicopts [list "--magic" [dict get $::parameters m]]
} else {
	set magicopts {}
}


## Check if we should list file extensions understood.
if {[dict get $::parameters l]} {
	## Yes. Get file types understood by the file utility
	if {![catch {exec -ignorestderr -- file -l {*}$magicopts 2>/dev/null} data]} {
		## Default column widths.
		set ewidth 0
		set mwidth 0

		## Setup known extensions.
		set known {}
		foreach {extension mimetype name} $::filetypes {
			lappend known $extension

			## Update maximum column widths for output formatting.
			if {[string length $extension]>$ewidth} {
				set ewidth [string length $extension]
			}
			if {[string length $mimetype]>$mwidth} {
				set mwidth [string length $mimetype]
			}
		}

		## Parse returned filetypes.
		foreach line [split $data \n] {
			## Only care for "Strength" lines.
			if {[regexp {^Strength += +[[:digit:]]+@[[:digit:]]+: (.*) \[(.*)\]$} $line match name mimetype]} {
				## Remember filetypes.
				set extension [extension $mimetype]
				if {$extension ni $known} {
					lappend known $extension
					lappend ::filetypes $extension $mimetype $name
				}

				## Update maximum column widths for output formatting.
				if {[string length $extension]>$ewidth} {
					set ewidth [string length $extension]
				}
				if {[string length $mimetype]>$mwidth} {
					set mwidth [string length $mimetype]
				}
			}
		}

		## Return the filetypes, sorted by extension.
		foreach {extension mimetype name} [lsort -dictionary -stride 3 -index 0 $::filetypes] {
			puts [format "%-${ewidth}s %-${mwidth}s %s" $extension $mimetype $name]
		}
	}

	## Exit program
	exit 0
}

## Get the ctimes to consider.
set ctimes [parseTimerange [dict get $::parameters t]]

## Get the mtimes to consider.
set mtimes [parseTimerange [dict get $::parameters T]]

## Set maximum file size to consider.
set maxsize [dict get $::parameters S]
if {$maxsize ne {}} {
	switch -- [string index $maxsize end] {
		k       {set multiplier [expr {10**3}]}
		M       {set multiplier [expr {10**6}]}
		G       {set multiplier [expr {10**9}]}
		default {set multiplier 1}
	}
	if {[string index $maxsize end] in {k M G}} {
		set maxsize [string range $maxsize 0 end-1]
	}
	if {![string is integer $maxsize]} {
		## Not a valid file size
		puts stderr "Please specify a valid maximum file size."
		exit 32
	}
	set maxsize [expr {$multiplier*$maxsize}]
}

## Get filesystem to scan from command line.
if {[lindex $argv 0] eq {} || [set fs [readlink [lindex $argv 0]]] eq {}} {
	puts stderr "Please specify a block device or an XFS filesystem image."
	exit 32
}

## Check for the type of the filesystem node.
if {[file type $fs] ni [list blockSpecial file]} {
	## Something else.
	puts stderr "Please specify a block device or an XFS filesystem image."
	exit 32
}

## Get list of mounted filesystems.
if {[catch {exec -- mount} result]} {
	## Error during mount. Fail.
	puts stderr $result
	exit 32
}

## Parse list of mounted filesystems.
foreach line [split $result \n] {
	## Skip non-xfs entries.
	if {[lindex $line 4] ne "xfs"} continue

	## Skip non-matching entries.
	if {[readlink [lindex $line 0]] ne $fs} continue

	## Ensure our output directory isn't on the same filesystem as the device node.
	if {[mountpoint [dict get $::parameters o]] eq [lindex $line 2]} {
		puts stderr "Your output directory is  [file normalize [dict get $::parameters o]]
That is within the filesystem  [lindex $line 2]  you want to recover files
from. This isn't feasible as it would overwrite the deleted files you wanted to
recover. Please specify the option -o /path/to/output_directory on another (rw
mounted) filesystem or run xfs_undelete from within a directory on that
filesystem so the recovered files could be written there. They cannot be
recovered in place."
		exit 32
	}

	## Skip non-read-write filesystems.
	if {"rw" ni [split [string trim [lindex $line 5] "()"] ,]} continue

	## Check if the remount step should be skipped.
	if {[dict get $::parameters no-remount-readonly]} {
		## Confirm.
		puts -nonewline stderr "[lindex $argv 0] ($fs) is currently mounted read-write, but you
specified the --no-remount-readonly option. This is a convenience option meant
for the case you need to recover files from your root filesystem. You have to
make sure the filesystem was umounted or remounted read-only by another means,
for example a reboot. Otherwise you won't be able to recover recently deleted
files.

Type UNDERSTOOD if you have fully understood that: "
		if {[gets stdin] ne "UNDERSTOOD"} {
			## Log.
			puts stderr "Operation cancelled."
			exit 32
		}
	} else {
		## Log.
		puts stderr "[lindex $argv 0] ($fs) is currently mounted read-write. Trying to remount read-only."

		## The rw option has been found. Try to remount read-only.
		set lang $env(LANG)
		set env(LANG) C
		if {[catch {exec -- mount -oremount,ro [lindex $line 2]} err]} {
			switch -glob -- $err {
				{mount: only root can use "--options" option} {
					## Fail if we cannot remount due to missing permissions.
					puts stderr "Remount failed. Root privileges are required to run this command on this filesystem."
					exit 32
				}
				{mount: * is busy?} {
					puts stderr "Remount failed. $err"
					exit 32
				}
				"* mount point not mounted or bad option." {
					## Ignore this error.
				}
				default {
					## Error during mount. Fail.
					puts stderr $err
					exit 32
				}
			}
		}
		set env(LANG) $lang

		## Sucess. Log.
		puts stderr "Remount successful."
	}

	## Ignore multiple mounts of the same filesystem as they all share the same read-only option.
	break
}

## Open filesystem image.
if {[catch {open $fs r} fd]} {
	puts stderr "Opening of filesystem failed. $fd"
	exit 32
}

## No character set nor crlf translation.
fconfigure $fd -translation binary


## Create lost+found directory if nonexistent.
if {[catch {file mkdir [dict get $::parameters o]} err]} {
	puts stderr "Cannot create output directory. $err"
	exit 32
}

## No inodes checked so far.
set ichecked 0

## Read first superblock.
set data [read $fd $sectsize]

## Fail if this isn't an XFS superblock
if {[string range $data 0 3] ne "XFSB"} {
	puts stderr "This isn't an XFS filesystem or filesystem image."
	exit 32
}

## Get xfs configuration from filesystem superblock.
binary scan [string range $data   4   7] Iu blocksize
binary scan [string range $data   8  15] Wu dblocks
binary scan [string range $data  84  87] Iu agblocks
binary scan [string range $data  88  91] Iu agcount
binary scan [string range $data 102 103] Su sectsize
binary scan [string range $data 104 105] Su inodesize
binary scan [string range $data 106 107] Su inopblock
binary scan [string index $data     124] cu agblklog
binary scan [string range $data 128 136] Wu icount

## Set message formats.
set skformat "Skipping  inode %[string length $dblocks]d (%3.0f%%)\r"
set cmformat "Checking  inode %[string length $dblocks]d (%3.0f%%)\r"
set rmformat "Recovered file -> %s"
set dmformat "Done.           %[string length $dblocks]s         "
set offormat "No space left on output device.%[string length $dblocks]s         "


## Log.
puts stderr "Starting recovery."

## Run through all allocation groups.
for {set ag 0} {$ag<$agcount} {incr ag} {
	## Read inode B+tree information sector of this allocation group.
	seek $fd [expr {$blocksize*$agblocks*$ag+2*$sectsize}]
	set data [read $fd $sectsize]

	## Get allocation group inode root block.
	binary scan [string range $data 20 23] Iu agi_root

	## Start traversal of this allocation group's inode B+Tree with root block.
	traverseInodeTree $ag $agi_root
}


## Print completion message.
puts stderr [format $::dmformat {}]
