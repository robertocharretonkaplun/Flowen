"""Optional local interoperability test with the installed Codex app-server."""
import json
from pathlib import Path
from queue import Empty, Queue
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Thread
from time import monotonic


def smoke(server, work):
    db = work / "aceptación.sqlite3"
    config = "mcp_servers={lunqio_prueba={command=" + json.dumps(server.as_posix()) + \
             ",args=[\"--db\"," + json.dumps(db.as_posix(), ensure_ascii=False) + "]}}"
    proc = subprocess.Popen([shutil.which("codex") or "codex", "-c", config, "app-server"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            text=True, encoding="utf-8", cwd=work)
    inbox = Queue()
    def receive():
        for line in proc.stdout:
            inbox.put(json.loads(line))
        inbox.put(None)
    Thread(target=receive, daemon=True).start()
    seq = 0
    def send(packet):
        proc.stdin.write(json.dumps(packet) + "\n")
        proc.stdin.flush()
    def rpc(method, params):
        nonlocal seq
        seq += 1
        send({"id":seq,"method":method,"params":params})
        deadline = monotonic() + 45
        while True:
            try:
                reply = inbox.get(timeout=max(0, deadline-monotonic()))
            except Empty:
                raise TimeoutError(method) from None
            if reply is None:
                raise RuntimeError("Codex cerró la conexión.")
            if reply.get("id") == seq and "method" not in reply:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply["result"]
    try:
        rpc("initialize", {"clientInfo":{"name":"lunqio_acceptance","version":"1"},
                           "capabilities":{"experimentalApi": True}})
        send({"method":"initialized","params":{}})
        thread = rpc("thread/start", {"cwd":str(work), "ephemeral":True})["thread"]["id"]
        status = rpc("mcpServerStatus/list", {"threadId":thread,"serverName":"lunqio_prueba"})
        assert len(status["data"][0]["tools"]) == 8, "Codex no descubrió las ocho herramientas."
        def tool(name, **args):
            result = rpc("mcpServer/tool/call", {"threadId":thread, "server":"lunqio_prueba",
                         "tool":name, "arguments":args})
            assert not result.get("isError"), result
            return json.loads(result["content"][0]["text"])
        page = tool("create_page", title="Bitácora de prueba", blocks=[{"type":"paragraph","text":"Muestra local"}])
        hits = tool("search_notes",query="Muestra")
        assert hits["pages"][0]["id"] == page["id"]
        read = tool("get_page",id=page["id"])
        tool("apply_block_changes",id=page["id"],expected_revision=read["revision"],changes=[
            {"op":"insert","block":{"type":"task","text":"Revisar el borrador"}}])
        latest = tool("get_page",id=page["id"])
        assert latest["revision"] == 2 and latest["blocks"][1]["type"] == "task"
        print("Codex descubrió 8 herramientas y creó, buscó, leyó y modificó una página.")
    finally:
        proc.stdin.close()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    with TemporaryDirectory() as directory:
        smoke(Path(sys.argv[1]).resolve(strict=True), Path(directory))
