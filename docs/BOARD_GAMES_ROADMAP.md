# Board games roadmap

Version 0.2.1 organizes eight entries in the Board Games folder. Tic-Tac-Toe and Connect Four remain the two playable games. Gomoku, Reversi, Xiangqi, Banqi, Chess, and Shogi are previews with a localized coming-soon page; they have no start action, board, AI, or save namespace yet.

| Entry | Current availability | Future board requirements |
| --- | --- | --- |
| Tic-Tac-Toe | Playable | Preserve the existing offline computer and local two-player modes and saves. |
| Connect Four | Playable | Preserve the existing offline computer and local two-player modes, gravity, and saves. |
| Gomoku | Coming soon | Recognizable black and white stones on a two-dimensional intersection board; clear legal placement targets. |
| Reversi | Coming soon | Recognizable two-sided discs on a two-dimensional grid; clear placement and flipping feedback. |
| Xiangqi | Coming soon | Recognizable labeled Chinese pieces, river and palaces, and unambiguous intersection hitboxes. |
| Banqi | Coming soon | A half board with face-down pieces, explicit flip actions, recognizable revealed Chinese pieces, and clear flip and capture targets. |
| Chess | Coming soon | Recognizable two-dimensional piece silhouettes, contrasting squares, and explicit selection, destination, and promotion controls. |
| Shogi | Coming soon | Recognizable labeled pentagonal pieces, visible facing and promotion, and separate clear board and captured-piece drop targets. |

Every planned game must eventually support a fully offline computer opponent and local two-player play on one device. The local layout must accommodate players sitting opposite each other: orient controls and directional or labeled pieces appropriately for each side while keeping the logical board coordinates stable. Do not use a whole-screen rotation that makes the other player's controls unreadable.

Use recognizable two-dimensional boards and pieces, sufficient contrast, explicit selected and legal-move feedback, clear non-overlapping touch regions, and meaningful accessibility labels for position, piece, side, and available action. Preserve comfortable touch targets as the board scales; selection must never depend only on color or a decorative piece image's opaque pixels. VoiceOver and larger text must retain access to every legal action.

Before activating an entry, implement and test the actual rules, offline AI, local mode, pause and restoration, result handling, and replay. Add its real menu and save identity only at that point. `CatalogItemID` is a navigation identity and must not be decoded as `GameID`. Keep the existing eight `GameID` raw values and 0.1.x/0.2.0 save namespaces unchanged. Activation belongs in the central `GameCatalog` metadata, with explicit `parentID` membership in the Board Games folder; the folder's availability counts must follow the real playable children.
