xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "../modules/config.xqm";
import module namespace load = "http://dracor.org/ns/exist/load"
  at "../modules/load.xqm";

declare variable $local:corpusname external;

let $corpus := collection($config:data-root)/corpus[name = $local:corpusname]

return (
  util:log-system-out("Loading data for corpus: " || $local:corpusname),
  load:load-corpus($corpus)
)
