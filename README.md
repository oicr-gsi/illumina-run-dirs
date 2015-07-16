# run-dir-cleanup
Scripts for cleaning Illumina instrument run directories.

# TAB 20150716
# Some additional usful info

# Implement this alis to make it easy to find the next unclean run dir to start cleaning up
alias nextdir='cd $(find . -maxdepth 1 -type d \( -name "[0-9][0-9][0-9][0-9][0-9][0-9]_*" -o -name "." \) | sort -r | xargs -I{} bash -c "if [ ! -e "{}/checkRunBeforeCleanReport.txt" ];then echo {}; exit 255;fi" 2>/dev/null)'
