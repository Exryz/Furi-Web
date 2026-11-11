// ==============================================================================
// Furi-Web (フリー・ウェブ) - Core Gecko & Floorp Preferences
// ==============================================================================

// Enable userChrome.css / userContent.css stylesheets
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Enable SVG context properties in CSS (required for custom icons and SVGs)
user_pref("svg.context-properties.content.enabled", true);

// Enable modern CSS features
user_pref("layout.css.color-mix.enabled", true);
user_pref("layout.css.has-selector.enabled", true);

// Disable Firefox 131+ vertical sidebar revamp to use Floorp / Sidebery native layout
user_pref("sidebar.revamp", false);
user_pref("sidebar.visibility", "Always");
