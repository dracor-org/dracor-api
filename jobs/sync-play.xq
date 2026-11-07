xquery version "3.1";

import module namespace sync = "http://dracor.org/ns/exist/v1/sync" at "../modules/sync.xqm";

declare variable $local:corpusname external;

declare variable $local:playname external;

try { sync:play($local:corpusname, $local:playname) } catch * {
  util:log-system-out(
    "Sync of " ||
      $local:corpusname ||
      "/" ||
      $local:playname ||
      " failed: " ||
      $err:description
  )
}
