xquery version "3.1";

module namespace dt = "http://dracor.org/ns/exist/trigger";

import module namespace metrics = "http://dracor.org/ns/exist/metrics"
  at "metrics.xqm";
import module namespace drdf = "http://dracor.org/ns/exist/rdf" at "rdf.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace tei = "http://www.tei-c.org/ns/1.0";


declare function trigger:after-create-document($url as xs:anyURI) {
  if (doc($url)/tei:TEI) then
    (metrics:update($url), drdf:update($url))
  else (
    util:log("info", "ignoring creation of " || $url)
  )
};

declare function trigger:after-update-document($url as xs:anyURI) {
  if (doc($url)/tei:TEI) then
    (metrics:update($url), drdf:update($url))
  else (
    util:log("info", "ignoring update of " || $url)
  )
};

declare function trigger:before-delete-document($url as xs:anyURI) {
  if (doc($url)/tei:TEI) then
    let $paths := dutil:filepaths($url)
    return try {
      xmldb:remove($paths?collections?metrics, $paths?filename),
      xmldb:remove($paths?collections?rdf, $paths?playname || ".rdf.xml")
    } catch * {
      util:log("info", $err:description)
    }
  else (
    util:log("info", "ignoring deletion of " || $url)
  )
};
