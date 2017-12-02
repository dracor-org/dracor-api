xquery version "3.1";
(:~
 : loads all configured resources via their zip archive.
:)
import module namespace config = "http://dracor.org/ns/exist/config"
  at "modules/config.xqm";
import module namespace load = "http://dracor.org/ns/exist/load"
  at "modules/load.xqm";

<resources>
  {
    for $corpus in $config:corpora//corpus
    return
      <res>{load:load-archive($corpus/name, $corpus/archive)}</res>
  }
</resources>
