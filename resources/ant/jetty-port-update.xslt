<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0">
  <xsl:output method="xml"
    version="1.0"
    encoding="UTF-8"
    indent="no"
    doctype-public="-//Jetty//Configure//EN"
    doctype-system="http://www.eclipse.org/jetty/configure_9_3.dtd"/>
  <xsl:param name="customPort"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

<!--  <xsl:template match="SystemProperty[@name = 'jetty.port']">
      <xsl:copy>
        <xsl:apply-templates select="@*[not(. = 'default')]"/>
        <xsl:attribute name="default"><xsl:value-of select="$customPort"/></xsl:attribute>
      </xsl:copy>
  </xsl:template>-->
<!--  <xsl:template match="comment()"/>-->

  <xsl:template match="@default[parent::*[@name = 'jetty.port']]">
    <xsl:attribute name="default"><xsl:value-of select="$customPort"/></xsl:attribute>
  </xsl:template>
</xsl:stylesheet>
