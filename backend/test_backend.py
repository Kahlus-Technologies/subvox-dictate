"""Exercise the Convex HTTP API exactly as the app will. Usage: backend_test.py <deployment url>"""
import json, sys, uuid, urllib.request, io, zipfile
base = sys.argv[1]
def call(kind, path, args):
    req = urllib.request.Request(f"{base}/api/{kind}", json.dumps({"path": path, "args": args, "format": "json"}).encode(),
                                 {"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req))
    if r["status"] == "error":  # prod hides messages; ConvexError data carries the reason
        r["errorMessage"] = str(r.get("errorData") or r["errorMessage"])
    return r
def ok(cond, what): print(("ok  " if cond else "FAIL"), what); assert cond, what
iid = str(uuid.uuid4())
r = call("mutation", "uploads:uploadUrl", {"installId": iid}); ok(r["status"] == "error" and "consent" in r["errorMessage"], "upload refused before consent")
r = call("mutation", "uploads:uploadUrl", {"installId": "not-a-uuid"}); ok(r["status"] == "error", "bad install id refused")
ok(call("mutation", "uploads:consent", {"installId": iid, "consentVersion": 1, "shareAudio": False, "appVersion": "test"})["status"] == "success", "consent (motion only)")
buf = io.BytesIO(); z = zipfile.ZipFile(buf, "w"); z.writestr("motion.csv", "t,ax\n0,0\n"); z.writestr("words.json", "{}"); z.close()
def upload(blob):
    url = call("mutation", "uploads:uploadUrl", {"installId": iid})["value"]
    return json.load(urllib.request.urlopen(urllib.request.Request(url, blob, {"Content-Type": "application/zip"})))["storageId"]
sid = upload(buf.getvalue())
fin = lambda sid, name, audio: call("mutation", "uploads:finishUpload", {"installId": iid, "sessionName": name, "storageId": sid,
      "durationSeconds": 9.5, "motionSamples": 475, "words": 15, "hasAudio": audio})
r = fin(sid, "2026-11-11T184947-348-dictation", False); ok(r["status"] == "success" and r["value"]["duplicate"] is False, "session registered")
r = fin(upload(buf.getvalue()), "2026-11-11T184947-348-dictation", False); ok(r["value"]["duplicate"] is True, "duplicate session ignored")
r = fin(upload(buf.getvalue()), "s2-dictation", True); ok(r["status"] == "error" and "audio" in r["errorMessage"], "audio refused without audio consent")
r = fin(upload(buf.getvalue()), "../etc", False); ok(r["status"] == "error", "bad session name refused")
s = call("query", "uploads:myStats", {"installId": iid})["value"]; ok(s["sessions"] == 1 and s["words"] == 15, f"stats {s}")
r = call("mutation", "uploads:deleteMyData", {"installId": iid}); ok(r["value"]["deletedSessions"] == 1, "delete my data")
ok(call("query", "uploads:myStats", {"installId": iid})["value"]["sessions"] == 0, "nothing left after delete")
r = call("mutation", "uploads:uploadUrl", {"installId": iid}); ok(r["status"] == "error", "uploads refused after delete (consent withdrawn)")
print("all backend checks passed")
