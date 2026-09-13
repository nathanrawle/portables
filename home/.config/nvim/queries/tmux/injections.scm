; extends

(set_option_directive
  (command)
  (option) @_option
  (value
    content: (string) @injection.content)
  (#match? @_option "^status-format(\\[[0-9]+\\])?$")
  (#set! injection.language "tmuxf"))
