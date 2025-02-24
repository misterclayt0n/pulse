# Drawing optimizations
- [ ] Dirty flag system :
    `request_redraw` for explicit changes.
    `dirty_frame` for periodic updates (cursor blink).
    `dirty` flag in `Buffer` for cached line metrics.
- [ ] Window resize handling? 
- [ ] Cached line metrics - Pre-calculate line widths and lenghts during edits.
- [ ] Partial redraws - Only recalculate visible lines when scroll position changes. 
- [ ] Temporal cache validation - Uses frame timing to manage blink updates
