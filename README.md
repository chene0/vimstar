# vimstar\*

A Neovim plugin that surfaces better keystroke sequences as you edit.

## Architecture

### vimstar System Architecture

```mermaid
flowchart TD
    subgraph plugin["vimstar-plugin (nvim plugin)"]
        m_logger["Mutation Logger"]
        tui_invoker["TUI Invoker"]
    end

    subgraph engine["vimstar-engine (Rust)"]
        %% proposal: compute diff at this edge
        ipc_handler["IPC Handler"]

        transformer["Transformer Trait"]
        hardcoded["HardcodedStruct"]
        embedding["EmbeddingStruct"]

        ratatui["ratatui Dashboard"]
    end

    subgraph data["user data dir"]
        sqlite[("vimstar.db")]
        onnx[("model.onnx")]
    end

    m_logger -->|stdio/socket JSON| ipc_handler
    ipc_handler -->|delegates to| transformer
    transformer -->|implemented by| hardcoded
    transformer -->|implemented by| embedding

    embedding -->|loads| onnx

    ipc_handler -->|writes| sqlite

    tui_invoker -->|invokes| ratatui
    ratatui -->|reads| sqlite
```

### `vimstar-plugin` internals

```mermaid
flowchart TD
    tui_user_command["Dashboard user command"]
    
    subgraph tui_invoker["TUI Invoker"]
        create_tui_buf["Create Buffer"]
        open_tui_buf["Open Buffer"]
        open_tui_dash["Terminal open engine dashboard"]
    end
    
    on_key_event("on_key input")

    changetick_event("changetick event")

    subgraph m_logger["Mutation Logger"]
        append_keystroke["Append keystroke to current sequence buffer"]
    
        q_undo_increase{"Did undotree block count increase?"}

        no_op["no op"]

        seal_sequence["Seal current sequence as one mutation event"]
        emit_sequence["IPC Emit mutation event"]
        reset_sequence["Reset sequence buffer"]
    end

    tui_user_command --> create_tui_buf
    create_tui_buf --> open_tui_buf
    open_tui_buf --> open_tui_dash

    changetick_event -->|triggers|q_undo_increase 
    on_key_event -->|triggers| append_keystroke

    append_keystroke -.-> seal_sequence

    q_undo_increase -->|yes| seal_sequence
    seal_sequence --> emit_sequence
    emit_sequence --> reset_sequence

    q_undo_increase --> |no| no_op
```

#### IPC Message Format

**mutation** — emitted by the mutation logger on each sealed undo unit
```json
{ "type": "mutation", "keystrokes": [...], "before": [...], "after": [...] }
```
