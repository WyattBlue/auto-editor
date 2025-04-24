import express from "express";
import { exec } from "node:child_process";
import * as path from "path";

const app = express();

app.get("/app/{*splat}", (req, res) => {
  const newPath = req.path.replace("/app/", "/");
  res.redirect(301, `https://app.auto-editor.com${newPath}`);
});

app.get("/blog", (req, res) => { res.redirect(301, `https://basswood-io.com/blog`) });
app.get("/blog/{*splat}", (req, res) => {
  res.redirect(301, `https://basswood-io.com${req.path}`);
});

app.get("/options", (req, res) => {
  res.redirect(301, "https://auto-editor.com/ref/options");
});

app.use(express.static("public", {
  index: ["index.html"],
  extensions: ["html"],
  setHeaders: (res, filep, stat) => {
    if (path.extname(filep) === "") {
      res.set("Content-Type", "text/html");
    }
  }
}));

app.use((req, res) => {
  let options = {
    headers: {"Content-Type": "text/html"}
  };
  res.status(404).sendFile(path.join(__dirname, "public/404"), options);
});

app.listen(1337, (req, res) => console.log("running on http://localhost:1337"));
