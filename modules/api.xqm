xquery version "3.1";

module namespace api = "http://dracor.org/ns/exist/api";

import module namespace config = "http://dracor.org/ns/exist/config" at "config.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace repo = "http://exist-db.org/xquery/repo";
declare namespace expath = "http://expath.org/ns/pkg";
declare namespace json = "http://www.w3.org/2013/XSL/json";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare
  %rest:GET
  %rest:path("/dracor")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:darcor() {
    let $expath := config:expath-descriptor()
    let $repo := config:repo-descriptor()
    return
      <info>
        <x>
          <y>kfmsldk</y>
          <y>ksld</y>
        </x>
        <name>{$expath/expath:title/string()}</name>
        <version>{$expath/@version/string()}</version>
        <status>{$repo/repo:status/string()}</status>
      </info>
};

declare
  %rest:GET
  %rest:path("/info.xml")
  %rest:produces("application/xml")
function api:info-xml() {
    let $expath := config:expath-descriptor()
    let $repo := config:repo-descriptor()
    return
      <info>
        <name>{$expath/expath:title/string()}</name>
        <version>{$expath/@version/string()}</version>
        <status>{$repo/repo:status/string()}</status>
      </info>
};

declare
  %rest:GET
  %rest:path("/resources")
  %rest:produces("application/xml", "text/xml")
function api:resources() {
  rest:resource-functions()
};
