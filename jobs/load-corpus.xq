xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "../modules/config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "../modules/util.xqm";
import module namespace load = "http://dracor.org/ns/exist/v1/load" at "../modules/load.xqm";
import module namespace resolver = "http://dracor.org/ns/exist/v1/resolver" at "../modules/resolver.xqm";

declare variable $local:corpusname external;

let $corpus := dutil:get-corpus($local:corpusname)

return (
  util:log-system-out("Loading data for corpus: " || $local:corpusname),
  util:log-system-out($corpus),
  (:
   : Refresh the version index of this corpus (versioned /id/ resolver).
   : Before load:load-corpus, which ends the job with an error (its result
   : does not match its declared type xs:string*), so nothing after it runs.
   :)
  util:log-system-out(
    serialize(
      resolver:refresh-corpus($local:corpusname),
      map {"method": "json"}
    )
  ),
  load:load-corpus($corpus)
)
