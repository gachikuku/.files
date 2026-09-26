# Load the TypeSafe/Jev API key from the macOS login Keychain for every zsh.
# The lookup is silent when no key has been stored yet.
if typesafe_api_key=$(/usr/bin/security find-generic-password \
  -a "$(/usr/bin/id -un)" \
  -s "typesafe.ai" \
  -w 2>/dev/null); then
  export TYPESAFE_API_KEY="$typesafe_api_key"
fi
unset typesafe_api_key
