---
description: Answer an Echo API question from the reference, not from memory
argument-hint: "<namespace or call>"
---
Answer this from `reference/api.md`, and cite the section: ${@:-process::read_uint64}

If the call does not exist, say so and give the real equivalent from
`reference/_API_CONTRACT.md`. Do not guess a signature. Include the return-value
semantics and any context restriction (render thread only, needs an attached
process, out-param form).
