// Pure model functions, shared by the QML panel and Node regression tests.
function clean(value) {
  return String(value || "").replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim();
}

function identity(window, entries) {
  var cls = clean(window.class || window.initialClass);
  var keys = [cls.toLowerCase(), clean(window.initialClass).toLowerCase()];
  var aliases = {
    "chrome-web.whatsapp.com__-default": {name: "WhatsApp", icon: "whatsapp"},
    "org.omarchy.btop": {name: "System monitor", icon: "utilities-system-monitor"},
    "chatgpt": {name: "ChatGPT", icon: "chatgpt"}
  };
  for (var a = 0; a < keys.length; a++) if (aliases[keys[a]]) return aliases[keys[a]];
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i];
    var id = clean(e.id).replace(/\.desktop$/, "").toLowerCase();
    var startup = clean(e.startupClass).toLowerCase();
    if ((id && keys.indexOf(id) >= 0) || (startup && keys.indexOf(startup) >= 0))
      return {name: clean(e.name) || cls, icon: e.icon || "application-x-executable"};
  }
  var fallback = cls.replace(/^org\.gnome\./, "").replace(/^org\.mozilla\./, "");
  if (fallback === "Nautilus") fallback = "Files";
  return {name: fallback ? fallback.charAt(0).toUpperCase() + fallback.slice(1) : "Unknown application", icon: "application-x-executable"};
}

function windows(snapshot, entries) {
  return (snapshot.windows || []).filter(function(w) { return w.workspace >= 0; }).map(function(w) {
    var app = identity(w, entries || []);
    return {address: w.address, name: app.name, icon: app.icon,
      title: clean(w.title || w.initialTitle) || "Untitled window",
      workspace: w.workspace, workspaceName: clean(w.workspaceName) || String(w.workspace), monitor: clean(w.monitor)};
  }).sort(function(a, b) {
    return a.workspace - b.workspace || a.name.localeCompare(b.name) || a.title.localeCompare(b.title) || a.address.localeCompare(b.address);
  });
}

function filter(rows, query) {
  var q = clean(query).toLowerCase();
  return rows.filter(function(w) {
    return (w.name + " " + w.title + " workspace " + w.workspaceName + " " + w.monitor).toLowerCase().indexOf(q) >= 0;
  });
}

function selected(rows, address) {
  return rows.some(function(w) { return w.address === address; }) ? address : (rows.length ? rows[0].address : "");
}

function monitors(snapshot) {
  return (snapshot.monitors || []).slice().sort(function(a, b) { return a.x - b.x || a.y - b.y || a.name.localeCompare(b.name); });
}

function boardRows(rows, monitor) {
  var result = [], previous = null;
  rows.filter(function(w) { return w.monitor === monitor; }).forEach(function(w) {
    if (w.workspace !== previous) { result.push({header: true, workspaceName: w.workspaceName}); previous = w.workspace; }
    result.push(w);
  });
  return result;
}
