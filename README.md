# Emacs go-escape-analysis mode


This minor mode displays Go escape analysis information inline with your code.
It runs the Go compiler with escape analysis flags and adds the results as
annotations to the relevant lines in the buffer.

# Usage

```elisp
(require 'go-escape-analysis-mode)
```

Turn on the minor mode in any Go buffer to see variable escapes and variables moved to heap.

![Image](https://github.com/user-attachments/assets/675bfd10-672d-4f00-94c8-65268567d909)
