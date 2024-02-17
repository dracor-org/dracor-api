xquery version "3.1";

module namespace dt = "http://dracor.org/ns/exist/v1/trigger";

import module namespace metrics = "http://dracor.org/ns/exist/v1/metrics"
  at "metrics.xqm";
import module namespace drdf = "http://dracor.org/ns/exist/v1/rdf" at "rdf.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace tei = "http://www.tei-c.org/ns/1.0";


declare function trigger:after-create-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml") and doc($url)/tei:TEI) then
    (
      util:log-system-out("running CREATION TRIGGER for " || $url),
      metrics:update($url),
      metrics:update-sitelinks($url),
      drdf:update($url)
    )
  else ()
};

declare function trigger:after-update-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml") and doc($url)/tei:TEI) then
    (
      util:log-system-out("running UPDATE TRIGGER for " || $url),
      metrics:update($url),
      metrics:update-sitelinks($url),
      drdf:update($url)
    )
  else ()
};

declare function trigger:before-delete-document($url as xs:anyURI) {
  if (ends-with($url, "/tei.xml")) then
    util:log-system-out("about to DELETE " || $url)
  else ()
};
