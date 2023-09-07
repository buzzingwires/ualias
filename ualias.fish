complete --command ualias --no-files
complete --command ualias --description 'Leave the positional args blank to print aliases. Otherwise, to create aliases, valid formats are "<Alias Name>=<Alias Contents>" and "<Alias Name> <Alias Contents>"'
complete --command ualias --short-option d --long-option delete --no-files --require-parameter --arguments "$(ualias --print-format name)" --description "Delete the specified alias. No positional options may be used when this is specified."
complete --command ualias --short-option p --long-option post-instruction --description "When creating an alias, this is to be included after the arguments."
complete --command ualias --short-option P --long-option print-format --no-files --require-parameter --arguments "normal shell name" --description 'The format to print aliases in. Default is "normal".'
complete --command ualias --short-option h --long-option help --description "Print help, then quit."
complete --command ualias --short-option v --long-option verbose --description "Print non-error messages to stderr."
complete --command ualias --short-option o --long-option overwrite --description "Overwrite the alias if it already exists."
complete --command ualias --short-option s --long-option scripts-dir --require-parameter --description 'Choose where alias scripts are stored. Default is "/usr/local/bin/aliases"'
complete --command ualias --short-option l --long-option link-dir --require-parameter --description 'Choose where alias scripts are linked to. Default is "/usr/local/bin"'
