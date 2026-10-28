xquery version "3.1";

module namespace dt = "http://dracor.org/ns/exist/v1/trigger";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace metrics = "http://dracor.org/ns/exist/v1/metrics" at "metrics.xqm";
import module namespace drdf = "http://dracor.org/ns/exist/v1/rdf" at "rdf.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

declare function trigger:after-create-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml") and doc($url)/tei:TEI) then (
    util:log-system-out("running CREATION TRIGGER for " || $url),
    metrics:update($url),
    metrics:update-sitelinks($url),
    drdf:update-play($url)
  ) else (
  )
};

declare function trigger:after-update-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml") and doc($url)/tei:TEI) then (
    util:log-system-out("running UPDATE TRIGGER for " || $url),
    metrics:update($url),
    metrics:update-sitelinks($url),
    drdf:update-play($url)
  ) else (
  )
};

declare function trigger:before-delete-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml")) then
    util:log-system-out("about to DELETE " || $url)
  else (
  )
};

(:~
 : Remove the RDF of a corpus or play from Fuseki when its collection is
 : deleted (when deleting or reloading a corpus, deleting a play or removing
 : it through a webhook delivery).
 :)
declare function trigger:before-delete-collection($uri as xs:anyURI) {
  let $segments := tokenize(
    substring-after($uri, $config:corpora-root || "/"),
    "/"
  )
  return switch (count($segments))
    case 1 return
      drdf:fuseki-drop-corpus($segments[1])
    case 2 return
      drdf:fuseki-drop-play($segments[1], $segments[2])
    default return
      ()
};
