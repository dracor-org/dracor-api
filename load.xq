xquery version "3.1";

import module namespace xdb = "http://exist-db.org/xquery/xmldb";
import module namespace load = "http://dracor.org/ns/exist/load" at "modules/load.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

let $corpora := xdb:document("/db/apps/dracor/corpora.xml")

return
  <resources>
    {
      for $corpus in $corpora//corpus
      return
        <res>{load:load-archive($corpus/name, $corpus/archive)}</res>
    }
  </resources>
