xquery version "3.1";

module namespace dt = "http://dracor.org/ns/exist/trigger";

import module namespace metrics = "http://dracor.org/ns/exist/metrics"
  at "metrics.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace tei = "http://www.tei-c.org/ns/1.0";


declare function trigger:after-create-document($url as xs:anyURI) {
  metrics:update($url)
};

declare function trigger:after-update-document($url as xs:anyURI) {
  metrics:update($url)
};

declare function trigger:after-delete-document($url as xs:anyURI) {
  let $paths := dutil:filepaths($url)
  let $collection := $paths?collections?metrics
  let $resource := $paths?filename
  return xmldb:remove($collection, $resource)
};
