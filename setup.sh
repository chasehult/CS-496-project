SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

mkdir -p "${SCRIPT_DIR}/scripts"
mkdir -p "${SCRIPT_DIR}/data"

curl --silent "https://raw.githubusercontent.com/rxi/json.lua/master/json.lua" > "${SCRIPT_DIR}/scripts/json.lua"
