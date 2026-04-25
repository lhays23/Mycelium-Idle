const express = require('express');
const path = require('path');
const app = express();
const PORT = process.env.PORT || 3000;

// Required for Godot 4 web builds (SharedArrayBuffer)
app.use((req, res, next) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  next();
});

app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, () => {
  console.log(`Mycelium Idle running on port ${PORT}`);
});