# Drives zsh's completion system for one command line, as a reader pressing Tab would
# (CompletionTests). Run as `zsh -f complete.zsh <folder holding _peep> <throwaway folder> <command
# line>`. The child's HOME and ZDOTDIR are the throwaway folder, and `-f` here and in the child
# skips every startup file, so the reader's own zsh setup is never read.
#
# The child is an interactive zsh in a pseudo-terminal (zsh/zpty) with the folder first on
# `fpath` and `compinit` run. Its `compadd` prints each candidate as `MATCH:<word>` instead of
# adding it; everything else the child writes (zsh's own errors, such as `_arguments`') comes
# back too. Prints all of it; exits non-zero if the child didn't start or finish completing.
zmodload zsh/zpty zsh/zselect || exit 2
folder=$1
export HOME=$2 ZDOTDIR=$2
line=$3

zpty peep_completion zsh -f -i || exit 2
setup=(
  'PS1="" PS2="" RPS1=""; unsetopt zle_bracketed_paste'
  "fpath=(${(q)folder} \$fpath)"
  'autoload -Uz compinit && compinit -u -d "$HOME/.zcompdump"'
  # Calls that only collect matches (-O, -A, -D) are completion functions' own bookkeeping.
  'compadd() { if [[ ${@[1,(i)(-|--)]} == *-(O|A|D)\ * ]]; then builtin compadd "$@"; return; fi; local -a hits; builtin compadd -O hits "$@"; print -rl -- MATCH:${^hits}; }'
  'peep-completion-done() { print -r -- PEEP_COMPLETION_DONE; exit; }'
  'comppostfuncs=(peep-completion-done)'
  'bindkey "^I" complete-word'
  'print -r -- PEEP_COMPLETION_""READY'
)
for command in $setup; do
  zpty -w peep_completion "$command"
done

# Reads the child's output into $output until it contains $1 (at most 10 seconds).
await() {
  local chunk
  local deadline=$(( SECONDS + 10 ))
  while (( SECONDS < deadline )); do
    if zpty -r -t peep_completion chunk; then
      output+=$chunk
      [[ $output == *$1* ]] && return 0
    else
      zselect -t 5
    fi
  done
  return 1
}

output=
if ! await PEEP_COMPLETION_READY; then
  print -r -- "$output"
  print -r -- "complete.zsh: zsh didn't start"
  exit 3
fi
output=
zpty -w -n peep_completion "$line"$'\t'
await PEEP_COMPLETION_DONE
finished=$?
zpty -d peep_completion
print -r -- "$output"
if (( finished != 0 )); then
  print -r -- "complete.zsh: completion didn't finish"
  exit 4
fi
