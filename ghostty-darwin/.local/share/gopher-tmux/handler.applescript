on open location theURL
    set helperPath to (POSIX path of (path to home folder)) & ".local/share/gopher-tmux/open-gopher.sh"
    try
        do shell script "/bin/sh " & quoted form of helperPath & " " & quoted form of theURL
    on error errorMessage
        display alert "Could not open Gopher link" message errorMessage
    end try
end open location
