# Runs bash's completion function for one command line, as `complete -F` would on Tab
# (CompletionTests). Run as `bash --norc --noprofile complete.bash <peep.bash> <command line>`;
# a line ending in a space completes a new word. Prints each candidate as `MATCH:<word>`.
source "$1" || exit 2
line=$2
[[ "$(complete -p peep)" == *' -F _peep peep' ]] || exit 3

COMP_LINE=$line
COMP_POINT=${#line}
read -r -a COMP_WORDS <<< "$line"
if [[ $line == *' ' ]]; then
  COMP_WORDS+=('')
fi
COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
COMPREPLY=()
_peep peep "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD - 1]}"
for word in "${COMPREPLY[@]}"; do
  printf 'MATCH:%s\n' "$word"
done
