def owned_handler:
  type == "object"
  and .type == "command"
  and ((.command? // "") as $command
    | ($command | startswith("$HOME/.zfuns/taw-agent-status "))
      or ($command | startswith("\"$HOME/.zfuns/taw-agent-status\" ")));

def without_owned_handlers:
  if ((.hooks? | type) != "array") then
    error("hook group must contain a hooks array")
  else
    .hooks = [.hooks[] | select(owned_handler | not)]
  end;

if type != "object" then
  error("configuration root must be an object")
elif (.hooks? != null and (.hooks | type) != "object") then
  error("configuration hooks must be an object")
else
  .hooks = (.hooks // {})
end
| .hooks |= with_entries(
    if (.value | type) != "array" then
      error("hook event must contain an array")
    else
      .value = [.value[] | without_owned_handlers | select((.hooks | length) > 0)]
    end
  )
| reduce ($fragment[0].hooks | to_entries[]) as $event (
    .;
    .hooks[$event.key] = ((.hooks[$event.key] // []) + $event.value)
  )
