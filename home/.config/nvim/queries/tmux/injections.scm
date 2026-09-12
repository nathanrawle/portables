; extends

(set_option_directive
  (command)
  (option) @_option
  (value
    content: (string) @injection.content)
  (#eq? @_option "status-format")
  (#set! injection.language "tmuxf"))
