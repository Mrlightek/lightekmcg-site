# Lightek HTML & CSS theme starter

1. Open `index.html` in your browser and edit it in any text editor. Share `theme.css` across your HTML pages.
2. Put the shared `header` and `footer` at the top level of the home page’s `body`. Put page content inside `main`. The home header and footer are used throughout the activated theme.
3. Put `data-lightek-navigation` on a `nav` in the header. Lightek renders your site’s real menu there. The sample links work when you preview locally.
4. Keep a direct child of the store’s `main` marked `data-lightek-products`. Lightek inserts published products and native cart actions there. Keep headings and other design sections as separate children of `main`.
5. Use `data-lightek-route="store"` for the storefront and `data-lightek-route="cart"` for the cart. Leave ordinary HTML links for other pages. Lightek maps included page filenames to their published URLs.
6. Add more HTML pages if needed. Set `data-lightek-page="page"` on ordinary pages, `home` on the home page, `store` on the store, or `blog` on the journal. A blog page uses its `main` for the native journal.

## Install on a website

Zip the files together. In Dashboard → Design & Content → Site themes, select the intended website and upload the ZIP. Review the draft pages, publish the pages you want visitors to see, then activate the theme. For a site with an existing home page, review the imported home draft and choose what to publish or use as the site's landing content.

Use up to ten HTML pages and one shared CSS file. Use hosted HTTPS URLs for images and other media. Lightek handles navigation, product controls, cart and checkout. Imported scripts and custom form handlers are removed. Add products in Commerce to populate the store.
