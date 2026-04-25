/** @type {import('tailwindcss').Config} */
module.exports = {
  theme: {
    extend: {
      colors: {
        zent: {
          bg: "hsl(var(--zent-background) / <alpha-value>)",
          fg: "hsl(var(--zent-foreground) / <alpha-value>)",
          card: "hsl(var(--zent-card) / <alpha-value>)",
          cardFg: "hsl(var(--zent-card-foreground) / <alpha-value>)",
          primary: "hsl(var(--zent-primary) / <alpha-value>)",
          primaryFg: "hsl(var(--zent-primary-foreground) / <alpha-value>)",
          border: "hsl(var(--zent-border) / <alpha-value>)",
          mutedFg: "hsl(var(--zent-muted-foreground) / <alpha-value>)"
        }
      }
    }
  }
};

