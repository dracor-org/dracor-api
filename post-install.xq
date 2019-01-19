xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)
(: the target collection into which the app is deployed :)
declare variable $target external;

(:~
 : Prepare RDF index according to the exist-sparql module description.
 : @author Mathias Göbel
 : @see https://github.com/ljo/exist-sparql
:)
declare function local:prepare-rdf-index ()
as xs:boolean {
  (: prepare for RDF index :)
  let $rdf-collection := xmldb:create-collection("/", $config:rdf-root)
  let $rdf-conf-coll := xmldb:create-collection(
    "/",
    "/db/system/config" || $config:rdf-root
  )
  let $xconf :=
      <collection xmlns="http://exist-db.org/collection-config/1.0">
         <index xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <rdf />
         </index>
      </collection>
  let $config := xmldb:store($rdf-conf-coll, "collection.xconf", $xconf)
  return
    true()
};

(: elevate privileges for github webhook :)
let $webhook := xs:anyURI($target || '/github-webhook.xq')
let $sitelinks-job := xs:anyURI($target || '/jobs/sitelinks.xq')

(: register the RESTXQ module :)
let $restxq-module := xs:anyURI('modules/api.xpm')

return (
  local:prepare-rdf-index(),
  sm:chown($webhook, "admin"),
  sm:chgrp($webhook, "dba"),
  sm:chmod($webhook, 'rwsr-xr-x'),
  sm:chown($sitelinks-job, "admin"),
  sm:chgrp($sitelinks-job, "dba"),
  sm:chmod($sitelinks-job, 'rwsr-xr-x'),
  exrest:register-module($restxq-module),

  (: a note on using the RDF index :)
  util:log-system-out("To use the RDF index the database needs to be restarted. See ant target «exist-conf».")
)
