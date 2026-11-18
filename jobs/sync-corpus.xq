xquery version "3.1";

import module namespace sync = "http://dracor.org/ns/exist/v1/sync" at "../modules/sync.xqm";

declare variable $local:corpusname external;

try { sync:corpus($local:corpusname) } catch * {
  util:log-system-out(
    "Sync of corpus " || $local:corpusname || " failed: " || $err:description
  )
}
