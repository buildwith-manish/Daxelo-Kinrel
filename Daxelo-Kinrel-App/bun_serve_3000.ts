const WEB_DIR = "/home/z/my-project/Daxelo-Kinrel-App/build/web";

Bun.serve({
  port: 3000,
  async fetch(req) {
    const url = new URL(req.url);
    let pathname = url.pathname;
    if (pathname === "/") pathname = "/index.html";
    const file = Bun.file(WEB_DIR + pathname);
    if (await file.exists()) return new Response(file);
    const indexFile = Bun.file(WEB_DIR + "/index.html");
    if (await indexFile.exists()) return new Response(indexFile);
    return new Response("Not Found", { status: 404 });
  },
});
console.log("KINREL on :3000");
