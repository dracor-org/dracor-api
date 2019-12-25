xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)
(: the target collection into which the app is deployed :)
declare variable $target external;

(: We create an empty config file that can be populated by XQuery updates
 : from the deployment. :)
declare function local:create-config-file ()
as item()? {
  if(doc("/db/data/dracor/config.xml")/config) then
    ()
  else
    xmldb:store(
      "/db/data/dracor",
      "config.xml",
      <config></config>
    ),
    (: FIXME: find a better solution to protect the webhook secret :)
    sm:chmod(xs:anyURI("/db/data/dracor/config.xml"), 'rw-------')
};


(: elevate privileges for github webhook :)
let $webhook := xs:anyURI($target || '/modules/webhook.xqm')
let $sitelinks-job := xs:anyURI($target || '/jobs/sitelinks.xq')

(: register the RESTXQ module :)
let $restxq-module := xs:anyURI('modules/api.xpm')

return (
  local:create-config-file(),
  sm:chown($webhook, "admin"),
  sm:chgrp($webhook, "dba"),
  sm:chmod($webhook, 'rwsr-xr-x'),
  sm:chown($sitelinks-job, "admin"),
  sm:chgrp($sitelinks-job, "dba"),
  sm:chmod($sitelinks-job, 'rwsr-xr-x'),
  exrest:register-module($restxq-module),

  (: a note on using the RDF index :)
  util:log-system-out(
    "To use the RDF index the database needs to be restarted. "
  )
)
