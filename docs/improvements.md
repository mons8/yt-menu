Change file names to two worded hyphenateds
then verify and substantialte file locations in yt-menu (scripts but also env-setup)especially but also projectwide. Substansiate is to make them robust with new 
$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
logic

logic for Albums and Albums Plural, perhaps Songs, to replace custom directory with Enter Artist and Enter Album name which also reflects in ID3

Evaluate change of .cfg to .env. Changes needs to be made to several .sh files. Files should be created in 
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
Perhaps with a helper script such as this:
        #!/bin/bash

        # Adhere to the XDG Base Directory Specification.
        # Use ${VAR:-default} to provide a fallback if the environment variable is not set.
        APP_NAME="yt-menu"
        CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
        CONFIG_FILE="$CONFIG_DIR/config"

        # Ensure the user's configuration directory exists before trying to use it.
        mkdir -p "$CONFIG_DIR"

        # Now, check if the user's config file exists.
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "User config not found. Creating from default."
            # Copy the default config from your project's `etc` directory to the user's config location.
            # This assumes your script knows the location of the project's `etc` dir.
            # The `environment.sh` from `lib` should define this path.
            cp "$WORK_DIR/etc/config.defaults" "$CONFIG_FILE"
        fi

        # Now, open the user's config file for editing.
        # The user is always editing their own copy, never the repository's default.
        "${EDITOR:-nano}" "$CONFIG_FILE"

Ensure stuff is working,

then github:
# The `-b main` flag sets the default branch name to `main`.
# If you omit this, it may default to `master`. Adjust as needed.
git init

# Before adding files, create a .gitignore.
# You are remiss if you commit dependencies, build artifacts, or secrets.
# Example for a Node project:
echo "node_modules/\n.env\ndist/" > .gitignore

# Stage all files for the initial commit.
git add .

# Commit the staged files.
git commit -m "Initial commit"

# Link your local repository to the empty one on GitHub.
# 'origin' is the conventional alias for your primary remote.
# Replace the URL with the one you copied.
git remote add origin git@github.com:USERNAME/REPONAME.git

# Verify the remote was added correctly.
git remote -v

# Push your local 'main' branch to 'origin'.
# The `-u` flag sets the upstream tracking reference for the current branch.
# This allows you to use `git pull` and `git push` without arguments in the future.
git push -u origin main

THEN checkout new branch and begin working on integrating/sorting out mess inside /.wip-ignore
# The -b flag creates the new branch.
git checkout -b wip-integration

then to save to github
# The -u flag sets the upstream for this new branch.
git push -u origin refactor-authentication-logic

the merge with Pull Request on Github directly

Create installation script for /scripts

No regex for subs, example: --sub-langs "^en(-[a-zA-Z]+)*$"
This is default for -o: --output "%(channel)s - %(title)s.%(upload_date)s.%(autonumber)02d.%(ext)s"
Include %(upload_date)s in output-builder

Consolidate .cfg (.env) files
