; extends

; ---------------------------------------------------------
; GitHub Actions: steps: [ { … run: | … } ]  → bash
; Only match `run: |` inside a step (a list item under `steps:`)
; ---------------------------------------------------------
(block_mapping_pair
  key: (flow_node) @k_steps
  (#eq? @k_steps "steps")
  value: (block_node
    (block_sequence
      _*
      (block_sequence_item
        (block_node
          (block_mapping
            _*
            (block_mapping_pair
              key: (flow_node) @k_run
              (#eq? @k_run "run")
              value: (block_node (block_scalar) @injection.content))
            _*)))))
  (#set! injection.language "bash"))

; ---------------------------------------------------------
; actions/github-script: with: script: |  → javascript
; Allow any number of sibling nodes between keys
; ---------------------------------------------------------

; Case 1: uses comes before with
(block_mapping
  (block_mapping_pair
    key: (flow_node) @k_uses
    value: (flow_node) @v_uses
    (#eq? @k_uses "uses")
    (#match? @v_uses "^actions/github-script@"))
  _*

  (block_mapping_pair
    key: (flow_node) @k_with
    (#eq? @k_with "with")
    value: (block_node
      (block_mapping
        (block_mapping_pair
          key: (flow_node) @k_script
          (#eq? @k_script "script")
          value: (block_node (block_scalar) @injection.content)))))
  (#set! injection.language "javascript"))

; Case 2: with comes before uses
(block_mapping
  (block_mapping_pair
    key: (flow_node) @k_with
    (#eq? @k_with "with")
    value: (block_node
      (block_mapping
        (block_mapping_pair
          key: (flow_node) @k_script
          (#eq? @k_script "script")
          value: (block_node (block_scalar) @injection.content)))))
  _*

  (block_mapping_pair
    key: (flow_node) @k_uses
    value: (flow_node) @v_uses
    (#eq? @k_uses "uses")
    (#match? @v_uses "^actions/github-script@"))
  (#set! injection.language "javascript"))
