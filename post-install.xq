xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/v0/config"
  at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)
(: the target collection into which the app is deployed :)
declare variable $target external;

(: We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - DRACOR_API_BASE: base URI the DraCor API will be available under
 : - FUSEKI_SERVER: base URI of the fuseki server
 : - METRICS_SERVER: DraCor metrics service URI
 :)
declare function local:create-config-file ()
as item()? {
  if(doc("/db/data/dracor/config.xml")/config) then
    ()
  else
    util:log-system-out("Creating config.xml"),
    xmldb:store(
      "/db/data/dracor",
      "config.xml",
      <config>
        <api-base>
        {
          if (environment-variable("DRACOR_API_BASE")) then
            environment-variable("DRACOR_API_BASE")
          else "https://dracor.org/api"
        }
        </api-base>
        <services>
          <fuseki>
          {
            if (environment-variable("FUSEKI_SERVER")) then
              environment-variable("FUSEKI_SERVER")
            else "http://localhost:3030/dracor/"
          }
          </fuseki>
          <metrics>
          {
            if (environment-variable("METRICS_SERVER")) then
              environment-variable("METRICS_SERVER")
            else "http://localhost:8030/metrics/"
          }
          </metrics>
        </services>
      </config>
    )
};

(: We create an initial config file the values of which can be passed by the
 : following environment variables:
 :
 : - GITHUB_WEBHOOK_SECRET: secret for the GitHub webhook
 : - FUSEKI_SECRET: admin password for the fuseki server
 :)
declare function local:create-secrets-file ()
as item()? {
  if(doc("/db/data/dracor/secrets.xml")/secrets) then
    ()
  else
    util:log-system-out("Creating secrets.xml"),
    xmldb:store(
      "/db/data/dracor",
      "secrets.xml",
      <secrets>
        <fuseki>{environment-variable("FUSEKI_SECRET")}</fuseki>
        <gh-webhook>{environment-variable("GITHUB_WEBHOOK_SECRET")}</gh-webhook>
      </secrets>
    ),
    (: FIXME: find a better solution to protect the webhook secret :)
    sm:chmod(xs:anyURI("/db/data/dracor/secrets.xml"), 'rw-------')
};

(: elevate privileges for github webhook :)
let $webhook := xs:anyURI($target || '/modules/webhook.xqm')
let $sitelinks-job := xs:anyURI($target || '/jobs/sitelinks.xq')

(: register the RESTXQ module :)
let $restxq-module := xs:anyURI('modules/api.xpm')

return (
  local:create-config-file(),
  local:create-secrets-file(),
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
