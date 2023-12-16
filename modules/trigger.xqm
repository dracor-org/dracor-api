xquery version "3.1";

module namespace dt = "http://dracor.org/ns/exist/v1/trigger";

import module namespace metrics = "http://dracor.org/ns/exist/v1/metrics"
  at "metrics.xqm";
import module namespace drdf = "http://dracor.org/ns/exist/v1/rdf" at "rdf.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace tei = "http://www.tei-c.org/ns/1.0";


declare function trigger:after-create-document($url as xs:anyURI) {
  if (doc($url)/tei:TEI) then
    (
      util:log-system-out("running CREATION TRIGGER for " || $url),
      metrics:update($url),
      metrics:update-sitelinks($url),
      drdf:update($url)
    )
  else (
    util:log-system-out("ignoring creation of " || $url)
  )
};

declare function trigger:after-update-document($url as xs:anyURI) {
  if (doc($url)/tei:TEI) then
    (
      util:log-system-out("running UPDATE TRIGGER for " || $url),
      metrics:update($url),
      metrics:update-sitelinks($url),
      drdf:update($url)
    )
  else (
    util:log-system-out("ignoring update of " || $url)
  )
};

declare function trigger:before-delete-document($url as xs:anyURI) {
  if (doc($url)/tei:TEI) then
    let $paths := dutil:filepaths($url)
    let $id := dutil:get-play-wikidata-id(doc($url)/tei:TEI)
    return try {
      if ($id) then xmldb:remove($paths?collections?sitelinks, $id || '.xml') else (),
      xmldb:remove($paths?collections?metrics, $paths?filename),
      xmldb:remove($paths?collections?rdf, $paths?playname || ".rdf.xml")
    } catch * {
      util:log-system-out($err:description)
    }
  else (
    util:log-system-out("ignoring deletion of " || $url)
  )
};
