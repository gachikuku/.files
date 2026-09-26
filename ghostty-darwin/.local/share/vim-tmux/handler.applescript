use framework "Foundation"
use scripting additions

on open location theURL
    set urlPrefix to "cursor://file"
    if theURL does not start with urlPrefix then
        display alert "Could not open file in Vim" message "Expected a cursor://file/ URL"
        return
    end if

    set encodedPath to text ((length of urlPrefix) + 1) thru -1 of theURL
    set decodedPath to ((current application's NSString's stringWithString:encodedPath)'s stringByRemovingPercentEncoding()) as text
    my openFileSpecification(decodedPath)
end open location

on open openedItems
    repeat with openedItem in openedItems
        my openFileSpecification(POSIX path of openedItem)
    end repeat
end open

on openFileSpecification(fileSpecification)
    set helperPath to (POSIX path of (path to home folder)) & ".local/share/vim-tmux/open-file.sh"

    try
        do shell script "/bin/sh " & quoted form of helperPath & " " & quoted form of fileSpecification
    on error errorMessage
        display alert "Could not open file in Vim" message errorMessage
    end try
end openFileSpecification
