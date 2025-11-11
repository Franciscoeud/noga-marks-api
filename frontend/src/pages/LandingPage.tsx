import { useRef, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";

const primaryNav: Array<{ label: string; href: string; badge?: string }> = [
  { label: "Women", href: "#women" },
  { label: "Shoes", href: "#shoes" },
  { label: "Gift Guide", href: "#gift-guide" },
];

const megaMenuColumns = [
  {
    title: "Clothing",
    links: [
      "Shop All",
      "Leggings",
      "Sports Bras",
      "Sweatshirts & Hoodies",
      "Matching Sets",
      "Sweatpants",
      "Jackets & Coats",
      "Pants & Trousers",
      "Tops",
      "Shorts",
      "Dresses",
    ],
  },
  {
    title: "Top Picks",
    links: [
      "New Arrivals",
      "Best Sellers",
      "Back in Stock",
      "Last Few Pieces",
      "Fan Favorites",
    ],
  },
  {
    title: "Spotlight On",
    links: [
      "Alo + Kendall",
      "Studio to Street",
      "Cold Weather Edit",
      "Accolade Guide",
      "Lounge Luxe",
    ],
  },
  {
    title: "Shop by Activity",
    links: ["Yoga", "Pilates", "Run", "Lounge", "Court Sports", "Train"],
  },
  {
    title: "Accessories",
    links: [
      "Shop All",
      "Hair Accessories",
      "Hats",
      "Socks",
      "Mats & Equipment",
      "Gift Cards",
    ],
  },
];

const heroTiles = [
  {
    headline: "Peak Luxe Layers",
    supporting: "Proof that warmth can still wow.",
    cta: "Explore Jackets",
    href: "#outerwear",
    image:
      "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=900&q=80",
  },
  {
    headline: "The Outerwear Edit",
    supporting: "Peak perfection",
    cta: "Shop The Edit",
    href: "#outerwear",
    image:
      "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=900&q=80",
    featured: true,
  },
  {
    headline: "Apres Ski Essentials",
    supporting: "Off-duty comfort, on-slope style.",
    cta: "Shop Now",
    href: "#apres",
    image:
      "https://images.unsplash.com/photo-1516205651411-aef33a44f7c2?auto=format&fit=crop&w=900&q=80",
  },
];

const trendingCollections: Array<{
  title: string;
  description: string;
  image: string;
  href: string;
}> = [
  {
    title: "Luxe Lounge Sets",
    description: "Coordinated comfort that turns heads.",
    image:
      "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=700&q=80",
    href: "/collections/luxe-lounge-sets",
  },
  {
    title: "Studio to Street Sneaks",
    description: "Cushioned soles and minimalist details.",
    image:
      "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=700&q=80",
    href: "/collections/studio-to-street-sneaks",
  },
  {
    title: "Giftable Favorites",
    description: "Soft-touch layers for everyone on your list.",
    image:
      "https://images.unsplash.com/photo-1525507119028-ed4c629a60a3?auto=format&fit=crop&w=700&q=80",
    href: "/collections/giftable-favorites",
  },
  {
    title: "Court Ready Sets",
    description: "Performance fabrics with elevated tailoring.",
    image:
      "https://images.unsplash.com/photo-1512100356356-de1b84283e18?auto=format&fit=crop&w=700&q=80",
    href: "/collections/court-ready-sets",
  },
];

const giftGuideCollections: Array<{
  title: string;
  caption: string;
  image: string;
  href: string;
}> = [
  {
    title: "For The Homebody",
    caption: "Cashmere wraps and scented candle sets for slow Sundays.",
    image:
      "https://images.unsplash.com/photo-1514996937319-344454492b37?auto=format&fit=crop&w=800&q=80",
    href: "/gift-guide/homebody",
  },
  {
    title: "For The Athlete",
    caption: "Performance layers and recovery must-haves.",
    image:
      "https://images.unsplash.com/photo-1517960413843-0aee8e2b3285?auto=format&fit=crop&w=800&q=80",
    href: "/gift-guide/athlete",
  },
  {
    title: "For The Jet Setter",
    caption: "Travel-ready sets and elevated carry-ons.",
    image:
      "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=800&q=80",
    href: "/gift-guide/jet-setter",
  },
];

const reviewHighlights: Array<{
  title: string;
  quote: string;
  image: string;
  href: string;
}> = [
  {
    title: "Waffle Weekend Escape Mock Neck",
    quote:
      "This is the quintessential winter top. Cozy, warm, and easy to dress up or down.",
    image:
      "https://images.unsplash.com/photo-1516762689617-e1cffcef479d?auto=format&fit=crop&w=800&q=80",
    href: "/reviews/waffle-weekend-escape",
  },
  {
    title: "Aspen Love Puffer",
    quote: "Super warm and comfortable. The detachable hood is perfect for travel days.",
    image:
      "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=800&q=80",
    href: "/reviews/aspen-love-puffer",
  },
  {
    title: "Airlift Line Up Bra",
    quote: "Best support ever. The material feels fantastic and looks amazing - owning it in every color!",
    image:
      "https://images.unsplash.com/photo-1516205651411-aef33a44f7c2?auto=format&fit=crop&w=800&q=80",
    href: "/reviews/airlift-line-up",
  },
  {
    title: "Muse Sweatpant",
    quote: "These with the matching hoodie are the softest set I own. I'll be living in them all season.",
    image:
      "https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=800&q=80",
    href: "/reviews/muse-sweatpant",
  },
];

const finishingTouches: Array<{
  title: string;
  price: string;
  primaryImage: string;
  hoverImage: string;
  href: string;
}> = [
  {
    title: "Notable Beanie - Winter Frost",
    price: "277 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=640&q=80",
    href: "https://nogamarks.com/shop?add-to-cart=63",
  },
  {
    title: "Unisex Half-Crew Throwback Sock",
    price: "121 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1503341455253-b2e723bb3dbb?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1512436991641-6745cdb1723f?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/throwback-sock",
  },
  {
    title: "District Trucker Hat - Bone",
    price: "263 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1503341455253-b2e723bb3dbb?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/district-trucker-hat",
  },
  {
    title: "ALO Runner - Black/Black",
    price: "691 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1519744792095-2f2205e87b6f?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/alo-runner",
  },
  {
    title: "Performance Conquer Headband",
    price: "121 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/conquer-headband",
  },
  {
    title: "Performance Off-Duty Cap - Espresso",
    price: "241 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/off-duty-cap-espresso",
  },
  {
    title: "Performance Off-Duty Cap - White",
    price: "241 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/off-duty-cap-white",
  },
  {
    title: "Day And Night Boxer - Black",
    price: "135 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1516205651411-aef33a44f7c2?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/day-night-boxer",
  },
  {
    title: "District Trucker Hat - Bone II",
    price: "263 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/district-trucker-hat-bone-2",
  },
  {
    title: "ALO Sunset Sneaker - Black",
    price: "798 PEN",
    primaryImage:
      "https://images.unsplash.com/photo-1519744792095-2f2205e87b6f?auto=format&fit=crop&w=640&q=80",
    hoverImage:
      "https://images.unsplash.com/photo-1539185441755-769473a23570?auto=format&fit=crop&w=640&q=80",
    href: "/accessories/alo-sunset-sneaker",
  },
];

const styledLooks: Array<{
  id: string;
  handle: string;
  image: string;
  spots: Array<{
    id: string;
    label: string;
    price: string;
    href: string;
    top: string;
    left: string;
    align?: "left" | "right";
    placement?: "top" | "bottom";
  }>;
}> = [
  {
    id: "look-chailee-01",
    handle: "chaileeson",
    image:
      "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-chailee-01-top",
        label: "Polar Fleece Retreat Cover Up",
        price: "PEN 596",
        href: "/products/polar-fleece-retreat-cover-up",
        top: "28%",
        left: "24%",
        align: "left",
        placement: "bottom",
      },
      {
        id: "look-chailee-01-short",
        label: "Accolade Sweat Short",
        price: "PEN 341",
        href: "/products/accolade-sweat-short",
        top: "72%",
        left: "46%",
      },
    ],
  },
  {
    id: "look-carmella-01",
    handle: "carmellarose",
    image:
      "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-carmella-01-top",
        label: "Airbrush Scoop Bra",
        price: "PEN 421",
        href: "/products/airbrush-scoop-bra",
        top: "30%",
        left: "52%",
        placement: "bottom",
      },
      {
        id: "look-carmella-01-leg",
        label: "Airlift High-Waist Legging",
        price: "PEN 499",
        href: "/products/airlift-high-waist-legging",
        top: "75%",
        left: "60%",
      },
    ],
  },
  {
    id: "look-taylor-01",
    handle: "taylor_hill",
    image:
      "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-taylor-01-top",
        label: "Muse Hoodie",
        price: "PEN 481",
        href: "/products/muse-hoodie",
        top: "22%",
        left: "65%",
        placement: "bottom",
      },
      {
        id: "look-taylor-01-skirt",
        label: "Ribbed Tennis Skirt",
        price: "PEN 382",
        href: "/products/ribbed-tennis-skirt",
        top: "70%",
        left: "70%",
        align: "right",
      },
    ],
  },
  {
    id: "look-melissa-01",
    handle: "melissawoodhealth",
    image:
      "https://images.unsplash.com/photo-1518611012118-696072aa579a?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-melissa-01-bra",
        label: "Airlift Intrigue Bra",
        price: "PEN 399",
        href: "/products/airlift-intrigue-bra",
        top: "35%",
        left: "32%",
        placement: "bottom",
      },
      {
        id: "look-melissa-01-tight",
        label: "7/8 Airlift Legging",
        price: "PEN 472",
        href: "/products/78-airlift-legging",
        top: "70%",
        left: "45%",
      },
    ],
  },
  {
    id: "look-steph-01",
    handle: "steph_w",
    image:
      "https://images.unsplash.com/photo-1515378791036-0648a3ef77b2?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-steph-01-crew",
        label: "Accolade Crew",
        price: "PEN 556",
        href: "/products/accolade-crew",
        top: "22%",
        left: "50%",
        placement: "bottom",
      },
      {
        id: "look-steph-01-pant",
        label: "Accolade Sweatpant",
        price: "PEN 482",
        href: "/products/accolade-sweatpant",
        top: "72%",
        left: "42%",
        align: "left",
      },
    ],
  },
  {
    id: "look-kim-01",
    handle: "kim_sun",
    image:
      "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-kim-01-bodysuit",
        label: "Alosoft Highlight Bodysuit",
        price: "PEN 548",
        href: "/products/alosoft-highlight-bodysuit",
        top: "36%",
        left: "55%",
        placement: "bottom",
      },
      {
        id: "look-kim-01-belt",
        label: "Studio Belt Bag",
        price: "PEN 299",
        href: "/products/studio-belt-bag",
        top: "55%",
        left: "65%",
      },
    ],
  },
  {
    id: "look-natalia-01",
    handle: "nataliafit",
    image:
      "https://images.unsplash.com/photo-1556817411-31ae72fa3ea0?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-natalia-01-top",
        label: "Solar Flare Bra",
        price: "PEN 411",
        href: "/products/solar-flare-bra",
        top: "32%",
        left: "30%",
        placement: "bottom",
      },
      {
        id: "look-natalia-01-tight",
        label: "Solar Flare Legging",
        price: "PEN 468",
        href: "/products/solar-flare-legging",
        top: "78%",
        left: "42%",
      },
    ],
  },
  {
    id: "look-claire-01",
    handle: "claire_moves",
    image:
      "https://images.unsplash.com/photo-1512436991641-6745cdb1723f?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-claire-01-top",
        label: "Muse Hoodie",
        price: "PEN 481",
        href: "/products/muse-hoodie",
        top: "25%",
        left: "35%",
        placement: "bottom",
      },
      {
        id: "look-claire-01-bottom",
        label: "Varsity Short",
        price: "PEN 299",
        href: "/products/varsity-short",
        top: "75%",
        left: "50%",
      },
    ],
  },
  {
    id: "look-nik-01",
    handle: "runwithnik",
    image:
      "https://images.unsplash.com/photo-1518432031352-d6fc5c10da5a?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-nik-01-jacket",
        label: "Aspen Love Puffer",
        price: "PEN 698",
        href: "/products/aspen-love-puffer",
        top: "25%",
        left: "50%",
        placement: "bottom",
      },
      {
        id: "look-nik-01-tight",
        label: "High-Waist Pursuit Tight",
        price: "PEN 482",
        href: "/products/high-waist-pursuit-tight",
        top: "68%",
        left: "55%",
      },
    ],
  },
  {
    id: "look-lina-01",
    handle: "liftedbylina",
    image:
      "https://images.unsplash.com/photo-1483721310020-03333e577078?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-lina-01-top",
        label: "Amplify Seamless Bra",
        price: "PEN 421",
        href: "/products/amplify-seamless-bra",
        top: "32%",
        left: "52%",
        placement: "bottom",
      },
      {
        id: "look-lina-01-leg",
        label: "Seamless High-Waist Tight",
        price: "PEN 468",
        href: "/products/seamless-high-waist-tight",
        top: "72%",
        left: "55%",
      },
    ],
  },
  {
    id: "look-chiara-01",
    handle: "chiarawave",
    image:
      "https://images.unsplash.com/photo-1539185441755-769473a23570?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-chiara-01-coat",
        label: "Peak Sherpa Coat",
        price: "PEN 799",
        href: "/products/peak-sherpa-coat",
        top: "30%",
        left: "28%",
        align: "left",
        placement: "bottom",
      },
      {
        id: "look-chiara-01-boot",
        label: "Aspen Trail Boot",
        price: "PEN 689",
        href: "/products/aspen-trail-boot",
        top: "82%",
        left: "40%",
      },
    ],
  },
  {
    id: "look-sunny-01",
    handle: "sunny_coast",
    image:
      "https://images.unsplash.com/photo-1491553895911-0055eca6402d?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-sunny-01-tee",
        label: "Muse Everyday Tee",
        price: "PEN 312",
        href: "/products/muse-everyday-tee",
        top: "26%",
        left: "44%",
        placement: "bottom",
      },
      {
        id: "look-sunny-01-leg",
        label: "Alosoft Sunray Legging",
        price: "PEN 459",
        href: "/products/alosoft-sunray-legging",
        top: "70%",
        left: "58%",
      },
    ],
  },
  {
    id: "look-janelle-01",
    handle: "janelleyoga",
    image:
      "https://images.unsplash.com/photo-1504198453319-5ce911bafcde?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-janelle-01-mat",
        label: "Warrior Yoga Mat",
        price: "PEN 398",
        href: "/products/warrior-yoga-mat",
        top: "62%",
        left: "40%",
      },
      {
        id: "look-janelle-01-bra",
        label: "Alosoft Serenity Bra",
        price: "PEN 388",
        href: "/products/alosoft-serenity-bra",
        top: "30%",
        left: "58%",
        placement: "bottom",
      },
    ],
  },
  {
    id: "look-athleisure-01",
    handle: "athleisureclub",
    image:
      "https://images.unsplash.com/photo-1503341455253-b2e723bb3dbb?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-athleisure-01-cozy",
        label: "Voyager Overcoat",
        price: "PEN 889",
        href: "/products/voyager-overcoat",
        top: "28%",
        left: "60%",
        placement: "bottom",
      },
      {
        id: "look-athleisure-01-pant",
        label: "Accolade Cargo Pant",
        price: "PEN 512",
        href: "/products/accolade-cargo-pant",
        top: "78%",
        left: "50%",
      },
    ],
  },
  {
    id: "look-pilates-01",
    handle: "pilatespulse",
    image:
      "https://images.unsplash.com/photo-1517960413843-0aee8e2b3285?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-pilates-01-bra",
        label: "Wild Thing Bra",
        price: "PEN 382",
        href: "/products/wild-thing-bra",
        top: "35%",
        left: "42%",
        placement: "bottom",
      },
      {
        id: "look-pilates-01-tight",
        label: "Ribbed Highlight Legging",
        price: "PEN 468",
        href: "/products/ribbed-highlight-legging",
        top: "72%",
        left: "48%",
      },
    ],
  },
  {
    id: "look-court-01",
    handle: "court_ace",
    image:
      "https://images.unsplash.com/photo-1509223197845-458d87318791?auto=format&fit=crop&w=900&q=80",
    spots: [
      {
        id: "look-court-01-dress",
        label: "Grand Slam Dress",
        price: "PEN 572",
        href: "/products/grand-slam-dress",
        top: "35%",
        left: "60%",
        align: "right",
        placement: "bottom",
      },
      {
        id: "look-court-01-viso",
        label: "Court Visor",
        price: "PEN 186",
        href: "/products/court-visor",
        top: "18%",
        left: "46%",
        placement: "bottom",
      },
    ],
  },
];

const activitySpotlights: Array<{ label: string; href: string; image: string }> = [
  {
    label: "Yoga",
    href: "/collections/yoga",
    image:
      "https://images.unsplash.com/photo-1434682881908-b43d0467b798?auto=format&fit=crop&w=900&q=80",
  },
  {
    label: "Lounge",
    href: "/collections/lounge",
    image:
      "https://images.unsplash.com/photo-1514996937319-344454492b37?auto=format&fit=crop&w=900&q=80",
  },
  {
    label: "Pilates",
    href: "/collections/pilates",
    image:
      "https://images.unsplash.com/photo-1518611012118-696072aa579a?auto=format&fit=crop&w=900&q=80",
  },
  {
    label: "Run",
    href: "/collections/run",
    image:
      "https://images.unsplash.com/photo-1518432031352-d6fc5c10da5a?auto=format&fit=crop&w=900&q=80",
  },
  {
    label: "Train",
    href: "/collections/train",
    image:
      "https://images.unsplash.com/photo-1483721310020-03333e577078?auto=format&fit=crop&w=900&q=80",
  },
  {
    label: "Court Sports",
    href: "/collections/court-sports",
    image:
      "https://images.unsplash.com/photo-1509223197845-458d87318791?auto=format&fit=crop&w=900&q=80",
  },
];

const colorStories: Array<{
  label: string;
  description: string;
  image: string;
  href: string;
  accent: string;
}> = [
  {
    label: "Brownstone",
    description: "Round out the season with this rich, rustic shade.",
    image:
      "https://images.unsplash.com/photo-1503341455253-b2e723bb3dbb?auto=format&fit=crop&w=1000&q=80",
    href: "/collections/brownstone",
    accent: "bg-amber-900/90",
  },
  {
    label: "Winter Frost",
    description: "A blue so cool, it'll give you the chills.",
    image:
      "https://images.unsplash.com/photo-1514996937319-344454492b37?auto=format&fit=crop&w=1000&q=80",
    href: "/collections/winter-frost",
    accent: "bg-blue-200/90 text-slate-900",
  },
  {
    label: "Navy",
    description: "This modern classic goes with everything.",
    image:
      "https://images.unsplash.com/photo-1517960413843-0aee8e2b3285?auto=format&fit=crop&w=1000&q=80",
    href: "/collections/navy",
    accent: "bg-slate-900/90",
  },
  {
    label: "Espresso",
    description: "A deeply saturated shade with all-year appeal.",
    image:
      "https://images.unsplash.com/photo-1512100356356-de1b84283e18?auto=format&fit=crop&w=1000&q=80",
    href: "/collections/espresso",
    accent: "bg-orange-900/90",
  },
  {
    label: "Black",
    description: "The studio-to-street classic you can always count on.",
    image:
      "https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=1000&q=80",
    href: "/collections/black",
    accent: "bg-black/90",
  },
];

const footerColumns = [
  {
    heading: "Customer Service",
    links: [
      "Help Center",
      "Track My Order",
      "Shipping",
      "Returns & Exchanges",
      "Gift Card",
      "Gift Card Balance",
      "Size Guide",
      "Reviews",
    ],
  },
  {
    heading: "My Account",
    links: ["Login or Register", "Order History", "Shipping & Billing", "Refer a Friend"],
  },
  {
    heading: "Information",
    links: [
      "Aurea Access",
      "We Are Aurea",
      "Blog",
      "Studios",
      "Stores",
      "Events",
      "Pro Program",
      "Careers",
      "Wellness Club",
      "Aurea Gives",
    ],
  },
];

const socialLinks: Array<{ label: string; href: string; shorthand: string }> = [
  { label: "Instagram", href: "#", shorthand: "IG" },
  { label: "TikTok", href: "#", shorthand: "TT" },
  { label: "Facebook", href: "#", shorthand: "FB" },
  { label: "X", href: "#", shorthand: "X" },
  { label: "Pinterest", href: "#", shorthand: "P" },
  { label: "YouTube", href: "#", shorthand: "YT" },
];

const legalLinks = ["Terms", "Privacy", "Cookie Policy", "Cookie Preferences"];

function IconButton({ label, children }: { label: string; children: ReactNode }) {
  return (
    <button
      type="button"
      className="flex h-9 w-9 items-center justify-center rounded-full border border-slate-200 text-slate-700 transition hover:border-slate-900 hover:text-slate-900"
      aria-label={label}
    >
      {children}
    </button>
  );
}

function OutlineIcon({ path }: { path: string }) {
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor">
      <path d={path} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function StarIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4 fill-current text-amber-500" aria-hidden="true">
      <path d="M12 2.5l2.9 6.08 6.7.97-4.8 4.72 1.13 6.63L12 17.98l-5.93 3.12 1.13-6.63-4.8-4.72 6.7-.97z" />
    </svg>
  );
}

function ArrowButton({
  direction,
  onClick,
  disabled,
}: {
  direction: "left" | "right";
  onClick: () => void;
  disabled?: boolean;
}) {
  const icon =
    direction === "left"
      ? "M15 18l-6-6 6-6"
      : "M9 6l6 6-6 6";

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="pointer-events-auto inline-flex h-10 w-10 items-center justify-center rounded-full border border-slate-300 bg-white text-slate-700 shadow-sm transition hover:border-slate-900 hover:text-slate-900 disabled:cursor-not-allowed disabled:opacity-40"
      aria-label={direction === "left" ? "Anterior" : "Siguiente"}
    >
      <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor">
        <path d={icon} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    </button>
  );
}

export function LandingPage() {
  const finishingTouchesRef = useRef<HTMLDivElement>(null);
  const styledLooksRef = useRef<HTMLDivElement>(null);
  const [activePin, setActivePin] = useState<string | null>(null);

  const scrollCarousel = (direction: "left" | "right") => {
    const container = finishingTouchesRef.current;
    if (!container) return;
    const scrollAmount = container.clientWidth;
    container.scrollBy({
      left: direction === "left" ? -scrollAmount : scrollAmount,
      behavior: "smooth",
    });
  };
  const scrollStyledLooks = (direction: "left" | "right") => {
    const container = styledLooksRef.current;
    if (!container) return;
    const scrollAmount = container.clientWidth;
    container.scrollBy({
      left: direction === "left" ? -scrollAmount : scrollAmount,
      behavior: "smooth",
    });
  };
  const togglePin = (id: string) => {
    setActivePin((prev) => (prev === id ? null : id));
  };

  return (
    <div className="min-h-screen bg-white text-slate-900">
      <div className="bg-slate-800 px-4 text-center text-xs font-semibold uppercase tracking-[0.2em] text-white sm:text-sm">
        Free Shipping &amp; Free Returns on Every Order
      </div>

      <header className="sticky top-0 z-20 border-b border-slate-200 bg-white/95 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-6 px-6 py-4 lg:grid lg:grid-cols-[auto_1fr_auto]">
          <Link to="/" className="flex items-center gap-3">
            <img
              src="/aurea-logo.svg"
              alt="Aurea"
              className="h-9 w-auto"
              loading="lazy"
            />
          </Link>
          <nav className="hidden items-center gap-8 lg:flex lg:justify-center">
            {primaryNav.map((item) => (
              <div key={item.label} className="group relative">
                <a
                  href={item.href}
                  className="text-sm font-semibold uppercase tracking-[0.18em] text-slate-700 transition hover:text-slate-900 hover:underline hover:decoration-2 hover:decoration-slate-900 hover:underline-offset-4 group-hover:text-slate-900 group-hover:underline group-hover:decoration-2 group-hover:decoration-slate-900 group-hover:underline-offset-4"
                >
                  {item.label}
                  {item.badge && (
                    <span className="ml-1 rounded-full bg-slate-900 px-2 py-0.5 text-[10px] font-bold text-white">
                      {item.badge}
                    </span>
                  )}
                </a>
                <div className="pointer-events-none absolute left-1/2 top-full z-20 w-[calc(100vw-2rem)] max-w-6xl -translate-x-1/2 px-4 sm:px-8 group-hover:pointer-events-auto">
                  <div className="invisible mx-auto mt-4 w-full translate-y-2 rounded-3xl border border-slate-200 bg-white p-8 sm:p-10 shadow-2xl opacity-0 transition duration-200 group-hover:visible group-hover:translate-y-0 group-hover:opacity-100 group-hover:pointer-events-auto">
                    <div className="grid grid-cols-5 gap-8 text-sm">
                      {megaMenuColumns.map((column) => (
                        <div key={column.title}>
                          <h4 className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">
                            {column.title}
                          </h4>
                          <ul className="mt-3 space-y-2">
                            {column.links.map((link) => (
                              <li key={link}>
                                <a
                                  href="#"
                                  className="text-slate-700 transition hover:text-slate-900 hover:underline hover:underline-offset-4 hover:decoration-2 hover:decoration-slate-900 focus-visible:text-slate-900 focus-visible:underline focus-visible:underline-offset-4 focus-visible:decoration-2 focus-visible:decoration-slate-900"
                                >
                                  {link}
                                </a>
                              </li>
                            ))}
                          </ul>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </nav>
          <div className="hidden items-center gap-3 lg:flex lg:justify-self-end">
            <IconButton label="Buscar">
              <OutlineIcon path="M21 21l-4.35-4.35M18 10.5a7.5 7.5 0 11-15 0 7.5 7.5 0 0115 0z" />
            </IconButton>
            <IconButton label="Iniciar sesion">
              <OutlineIcon path="M12 12a4 4 0 100-8 4 4 0 000 8zm6 8c0-3.313-2.687-6-6-6s-6 2.687-6 6" />
            </IconButton>
            <IconButton label="Lista de deseos">
              <OutlineIcon path="M12 20s-7-4.5-7-10a4 4 0 118-0 4 4 0 118 0c0 5.5-7 10-7 10z" />
            </IconButton>
            <IconButton label="Carrito">
              <OutlineIcon path="M6 6h15l-1.5 9h-12zM6 6l-1-3H3M9 21a1 1 0 100-2 1 1 0 000 2zm8 0a1 1 0 100-2 1 1 0 000 2z" />
            </IconButton>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl space-y-20 px-4 pb-24 pt-6 sm:px-6 lg:px-8">
        <section className="grid gap-4 md:grid-cols-3">
          {heroTiles.map((tile) => (
            <article
              key={tile.headline}
              className="group relative flex min-h-[22rem] overflow-hidden rounded-3xl bg-slate-900 text-white shadow-xl md:min-h-0 md:aspect-[4/5]"
            >
              <img
                src={tile.image}
                alt={tile.headline}
                className="h-full w-full object-cover transition duration-700 group-hover:scale-105"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-slate-950/80 via-slate-900/20 to-slate-900/0" />
              <div className="absolute inset-0 flex flex-col justify-end p-6 sm:p-10">
                <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
                  {tile.headline}
                </h2>
                <p className="mt-3 max-w-sm text-sm text-slate-100 sm:text-base">
                  {tile.supporting}
                </p>
                <a
                  href={tile.href}
                  className="mt-6 w-fit rounded-full bg-white px-6 py-2 text-sm font-semibold uppercase tracking-[0.25em] text-slate-900 transition hover:bg-slate-900 hover:text-white"
                >
                  {tile.cta}
                </a>
              </div>
            </article>
          ))}
        </section>

        <section id="trending" className="space-y-6">
          <header className="text-center">
            <h3 className="text-4xl font-semibold uppercase tracking-[0.2em] text-slate-900">
              Trending Now
            </h3>
          </header>
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
            {trendingCollections.map((collection) => (
              <a
                key={collection.title}
                href={collection.href}
                className="group flex h-full flex-col overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-md transition hover:-translate-y-1 hover:shadow-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900"
              >
                <div className="relative h-64 overflow-hidden">
                  <img
                    src={collection.image}
                    alt={collection.title}
                    className="h-full w-full object-cover transition duration-700 group-hover:scale-105"
                  />
                  <div className="absolute inset-0 bg-gradient-to-t from-slate-900/70 via-slate-900/10 to-transparent opacity-0 transition group-hover:opacity-100" />
                </div>
                <div className="flex flex-1 flex-col p-6">
                  <h4 className="text-lg font-semibold tracking-tight text-slate-900">
                    {collection.title}
                  </h4>
                  <p className="mt-3 text-sm text-slate-600">{collection.description}</p>
                  <span className="mt-6 inline-flex items-center gap-2 text-sm font-semibold uppercase tracking-[0.25em] text-slate-900 transition group-hover:gap-3">
                    Shop Now
                    <span aria-hidden="true">{"->"}</span>
                  </span>
                </div>
              </a>
            ))}
          </div>
        </section>

        <section id="gift-guide" className="space-y-8">
          <header className="text-center">
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500">
              Aurea Gift Guide
            </p>
            <h3 className="mt-3 text-3xl font-semibold tracking-tight text-slate-900 sm:text-4xl">
              Thoughtful Picks For Every Occasion
            </h3>
          </header>
          <div className="grid gap-6 md:grid-cols-3">
            {giftGuideCollections.map((collection) => (
              <a
                key={collection.title}
                href={collection.href}
                className="group space-y-4 rounded-3xl border border-slate-200 bg-white p-4 shadow-lg transition hover:-translate-y-1 hover:shadow-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900"
              >
                <div className="relative overflow-hidden rounded-2xl">
                  <img
                    src={collection.image}
                    alt={collection.title}
                    className="h-80 w-full object-cover transition duration-700 group-hover:scale-105"
                  />
                  <div className="absolute inset-0 bg-gradient-to-t from-slate-900/50 via-transparent to-transparent opacity-0 transition group-hover:opacity-100" />
                  <span className="absolute bottom-4 left-4 rounded-full bg-white/90 px-4 py-1 text-xs font-semibold uppercase tracking-[0.3em] text-slate-900">
                    Shop Gifts
                  </span>
                </div>
                <div className="space-y-2 px-2 pb-2">
                  <h4 className="text-lg font-semibold tracking-tight text-slate-900">
                    {collection.title}
                  </h4>
                  <p className="text-sm text-slate-600">{collection.caption}</p>
                </div>
              </a>
            ))}
          </div>
        </section>

        <section id="reviews" className="space-y-10 border-t border-slate-200 pt-12">
          <header className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500">
                The Reviews Are In
              </p>
              <h3 className="mt-2 text-3xl font-semibold tracking-tight text-slate-900">
                Shop the styles getting five stars.
              </h3>
            </div>
            <a
              href="#top-rated"
              className="text-sm font-semibold uppercase tracking-[0.25em] text-slate-900 underline-offset-4 hover:underline"
            >
              Shop All Top Rated
            </a>
          </header>
          <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
            {reviewHighlights.map((review) => (
              <a
                key={review.title}
                href={review.href}
                className="group flex h-full flex-col gap-4 rounded-3xl border border-slate-200 bg-white p-3 shadow-sm transition hover:-translate-y-1 hover:shadow-xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900"
              >
                <div className="relative overflow-hidden rounded-2xl">
                  <img
                    src={review.image}
                    alt={review.title}
                    className="h-80 w-full object-cover transition duration-700 group-hover:scale-105"
                  />
                </div>
                <div className="space-y-3 px-3 pb-4">
                  <div className="flex items-center gap-1 text-amber-400" aria-label="Rated five stars">
                    {Array.from({ length: 5 }).map((_, index) => (
                      <StarIcon key={`${review.title}-star-${index}`} />
                    ))}
                  </div>
                  <h4 className="text-lg font-semibold tracking-tight text-slate-900">{review.title}</h4>
                  <p className="text-sm text-slate-600">"{review.quote}"</p>
                  <span className="inline-flex items-center gap-2 text-sm font-semibold uppercase tracking-[0.25em] text-slate-900">
                    Read Review
                    <span aria-hidden="true">{"->"}</span>
                  </span>
                </div>
              </a>
            ))}
          </div>
        </section>

        <section id="finishing-touches" className="space-y-8 border-t border-slate-200 pt-12">
          <header className="flex items-center justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500">
                Finishing Touches
              </p>
              <h3 className="mt-2 text-3xl font-semibold tracking-tight text-slate-900">
                Accessories that finish the look.
              </h3>
            </div>
            <a
              href="/collections/accessories"
              className="text-sm font-semibold uppercase tracking-[0.25em] text-slate-900 underline-offset-4 hover:underline"
            >
              Shop Accessories
            </a>
          </header>

          <div className="relative">
            <div className="pointer-events-none absolute inset-y-0 left-0 z-10 hidden w-32 bg-gradient-to-r from-white via-white/70 to-transparent lg:block" />
            <div className="pointer-events-none absolute inset-y-0 right-0 z-10 hidden w-32 bg-gradient-to-l from-white via-white/70 to-transparent lg:block" />
            <div className="absolute inset-y-0 left-0 z-20 hidden items-center pl-4 lg:flex">
              <ArrowButton direction="left" onClick={() => scrollCarousel("left")} />
            </div>
            <div className="absolute inset-y-0 right-0 z-20 hidden items-center pr-4 lg:flex">
              <ArrowButton direction="right" onClick={() => scrollCarousel("right")} />
            </div>
            <div
              ref={finishingTouchesRef}
              className="flex gap-6 overflow-x-auto scroll-smooth pb-4"
            >
              {finishingTouches.map((item) => (
                <a
                  key={item.title}
                  href={item.href}
                  className="group w-[220px] flex-shrink-0"
                >
                  <div className="relative aspect-[3/4] overflow-hidden border border-slate-200 bg-slate-50">
                    <img
                      src={item.primaryImage}
                      alt={item.title}
                      className="h-full w-full object-cover transition duration-500 group-hover:opacity-0"
                    />
                    <img
                      src={item.hoverImage}
                      alt={`${item.title} alternate`}
                      className="absolute inset-0 h-full w-full object-cover opacity-0 transition duration-500 group-hover:opacity-100"
                    />
                  </div>
                  <div className="mt-4 space-y-1">
                    <p className="text-sm font-semibold tracking-tight text-slate-900">
                      {item.title}
                    </p>
                    <p className="text-sm text-slate-600">{item.price}</p>
                  </div>
                </a>
              ))}
            </div>

            <div className="mt-4 flex items-center justify-between lg:hidden">
              <ArrowButton direction="left" onClick={() => scrollCarousel("left")} />
              <ArrowButton direction="right" onClick={() => scrollCarousel("right")} />
            </div>
          </div>
        </section>

        <section
          id="leggings-guide"
          className="relative left-1/2 right-1/2 w-screen -translate-x-1/2 border border-slate-200"
        >
          <div className="relative h-[26rem] w-full overflow-hidden">
            <img
              src="https://images.unsplash.com/photo-1518611012118-696072aa579a?auto=format&fit=crop&w=2000&q=80"
              alt="Leggings guide hero"
              loading="lazy"
              className="h-full w-full object-cover"
            />
            <div className="absolute inset-0 bg-gradient-to-r from-slate-900/70 via-slate-900/30 to-transparent" />
            <div className="absolute inset-0 flex flex-col items-center justify-center p-6 text-center text-white">
              <p className="text-sm font-semibold uppercase tracking-[0.4em] text-white/80">
                Fit for every move
              </p>
              <h3 className="mt-4 text-4xl font-semibold tracking-[0.2em]">
                The Leggings Guide
              </h3>
              <p className="mt-3 max-w-2xl text-sm text-white/80">
                Compare inseams, fabrics, and studio-to-street finishes in one place.
              </p>
              <a
                href="/guides/leggings"
                className="mt-8 inline-flex items-center justify-center rounded-full bg-white px-8 py-3 text-sm font-semibold uppercase tracking-[0.35em] text-slate-900 transition hover:bg-slate-100"
              >
                Learn More
              </a>
            </div>
          </div>
        </section>

        <section id="shop-by-activity" className="space-y-10 border-t border-slate-200 py-12">
          <header className="text-center">
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500">
              Shop By Activity
            </p>
            <h3 className="mt-2 text-3xl font-semibold tracking-tight text-slate-900">
              Find the set that moves with you.
            </h3>
          </header>
          <div className="grid gap-6 grid-cols-2 sm:grid-cols-3 lg:grid-cols-6">
            {activitySpotlights.map((activity) => (
              <div key={activity.label} className="space-y-3">
                <a
                  href={activity.href}
                  className="group block overflow-hidden border border-slate-200 bg-white shadow-md transition hover:-translate-y-1 hover:shadow-xl"
                >
                  <img
                    src={activity.image}
                    alt={activity.label}
                    loading="lazy"
                    className="aspect-[3/4] w-full object-cover transition duration-700 group-hover:scale-105"
                  />
                </a>
                <a
                  href={activity.href}
                  className="block text-center text-sm font-semibold uppercase tracking-[0.3em] text-slate-900 transition hover:underline"
                >
                  {activity.label}
                </a>
              </div>
            ))}
          </div>
        </section>

        <section id="shop-by-color" className="space-y-10 border-t border-slate-200 py-12">
          <header className="text-center">
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500">
              Shop By Color
            </p>
            <h3 className="mt-2 text-3xl font-semibold tracking-tight text-slate-900">
              Choose a palette and start layering.
            </h3>
          </header>
          <div className="grid gap-6 lg:grid-cols-5">
            {colorStories.map((story) => (
              <a
                key={story.label}
                href={story.href}
                className="group flex h-full flex-col overflow-hidden border border-slate-200 bg-white shadow-md transition hover:-translate-y-1 hover:shadow-xl"
              >
                <div className="relative h-72 overflow-hidden">
                  <img
                    src={story.image}
                    alt={`Shop ${story.label}`}
                    loading="lazy"
                    className="h-full w-full object-cover transition duration-700 group-hover:scale-105"
                  />
                  <div className="absolute inset-x-0 bottom-0 p-5 text-white">
                    <div className={`rounded-2xl px-4 py-3 ${story.accent}`}>
                      <p className="text-xs font-semibold uppercase tracking-[0.4em]">
                        {story.label}
                      </p>
                      <p className="mt-2 text-sm">{story.description}</p>
                      <span className="mt-3 inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.3em]">
                        Shop {story.label}
                        <span aria-hidden="true">{"->"}</span>
                      </span>
                    </div>
                  </div>
                </div>
              </a>
            ))}
          </div>
        </section>

        <section
          id="styled-by-you"
          className="relative left-1/2 right-1/2 w-screen -translate-x-1/2 border-t border-slate-200 bg-slate-100 py-12"
        >
          <div className="mx-auto max-w-7xl space-y-10 px-4 sm:px-6 lg:px-8">
          <div className="text-center">
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-slate-500">
              Styled By You
            </p>
            <h3 className="mt-2 text-3xl font-semibold tracking-tight text-slate-900">
              Click to shop the looks you love!
            </h3>
          </div>
          <div className="relative">
            <div className="pointer-events-none absolute inset-y-0 left-0 z-10 hidden w-32 bg-gradient-to-r from-slate-100 via-slate-100/60 to-transparent lg:block" />
            <div className="pointer-events-none absolute inset-y-0 right-0 z-10 hidden w-32 bg-gradient-to-l from-slate-100 via-slate-100/60 to-transparent lg:block" />
            <div className="absolute inset-y-0 left-0 z-20 hidden items-center pl-6 lg:flex">
              <ArrowButton direction="left" onClick={() => scrollStyledLooks("left")} />
            </div>
            <div className="absolute inset-y-0 right-0 z-20 hidden items-center pr-6 lg:flex">
              <ArrowButton direction="right" onClick={() => scrollStyledLooks("right")} />
            </div>
            <div
              ref={styledLooksRef}
              className="flex gap-6 overflow-x-auto scroll-smooth pb-6"
            >
              {styledLooks.slice(0, 10).map((look) => (
                <article key={look.id} className="w-[320px] flex-shrink-0">
                  <div className="relative aspect-[3/4]">
                    <div className="absolute inset-0 overflow-hidden border border-slate-200 bg-slate-200">
                      <img
                        src={look.image}
                        alt={`Styled look by ${look.handle}`}
                        loading="lazy"
                        className="h-full w-full object-cover"
                      />
                    </div>
                    <div className="absolute inset-0">
                      {look.spots.map((spot) => {
                        const isActive = activePin === spot.id;
                        return (
                          <div
                            key={spot.id}
                            className="absolute"
                            style={{ top: spot.top, left: spot.left }}
                          >
                            <button
                              type="button"
                              onClick={() => togglePin(spot.id)}
                              className={`flex h-9 w-9 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border border-white/80 bg-white/90 text-slate-900 shadow-md transition hover:scale-105 ${
                                isActive ? "bg-slate-900 text-white" : ""
                              }`}
                              aria-label={`Ver ${spot.label}`}
                              aria-expanded={isActive}
                            >
                              {isActive ? (
                                <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor">
                                  <path d="M6 18L18 6M6 6l12 12" strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.8} />
                                </svg>
                              ) : (
                                <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor">
                                  <path d="M12 5v14M5 12h14" strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.8} />
                                </svg>
                              )}
                            </button>
                            {isActive && (
                              <div
                                className={`absolute z-10 min-w-[180px] rounded-2xl bg-white p-3 text-left shadow-2xl ${
                                  spot.align === "right" ? "right-0" : "left-0"
                                } ${spot.placement === "top" ? "bottom-full -mb-3" : "top-full mt-3"}`}
                              >
                                <p className="text-xs font-semibold uppercase tracking-[0.3em] text-slate-400">
                                  @{look.handle}
                                </p>
                                <p className="mt-1 text-sm font-semibold text-slate-900">{spot.label}</p>
                                <p className="text-sm text-slate-600">{spot.price}</p>
                                <a
                                  href={spot.href}
                                  className="mt-3 inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.3em] text-slate-900"
                                >
                                  Ver producto
                                  <span aria-hidden="true">{"->"}</span>
                                </a>
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                  <p className="mt-3 text-center text-sm font-semibold text-slate-600">@{look.handle}</p>
                </article>
              ))}
            </div>
            <div className="mt-4 flex items-center justify-between lg:hidden">
              <ArrowButton direction="left" onClick={() => scrollStyledLooks("left")} />
              <ArrowButton direction="right" onClick={() => scrollStyledLooks("right")} />
            </div>
          </div>
          </div>
        </section>
      </main>

      <footer className="bg-black text-white" aria-labelledby="footer-heading">
        <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
          <div className="grid gap-12 lg:grid-cols-[2fr_1fr]">
            <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-3">
              {footerColumns.map((column) => (
                <div key={column.heading}>
                  <p className="text-xs font-semibold uppercase tracking-[0.3em] text-white/60">
                    {column.heading}
                  </p>
                  <ul className="mt-4 space-y-3 text-sm text-white/80">
                    {column.links.map((link) => (
                      <li key={link}>
                        <a href="#" className="transition hover:text-white">
                          {link}
                        </a>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
            <div className="space-y-10">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.3em] text-white/60">
                  Get the App
                </p>
                <a
                  href="#"
                  className="mt-4 flex items-center gap-3 rounded-2xl border border-white/20 px-4 py-3 text-left transition hover:border-white"
                >
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white text-black">
                    <svg viewBox="0 0 24 24" className="h-6 w-6" aria-hidden="true">
                      <path
                        d="M17 2H7a2 2 0 00-2 2v16l7-3 7 3V4a2 2 0 00-2-2z"
                        fill="currentColor"
                      />
                    </svg>
                  </div>
                  <div>
                    <span className="block text-xs uppercase tracking-[0.3em] text-white/60">
                      Download on the
                    </span>
                    <span className="text-lg font-semibold leading-tight">App Store</span>
                  </div>
                </a>
              </div>
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.3em] text-white/60">
                  Language &amp; Ship To
                </p>
                <button
                  type="button"
                  className="mt-4 flex w-full items-center justify-between rounded-2xl border border-white/20 px-4 py-3 text-sm font-semibold uppercase tracking-[0.25em] text-white transition hover:border-white"
                >
                  <span>Peru · PEN</span>
                  <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor">
                    <path d="M6 9l6 6 6-6" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </button>
              </div>
            </div>
          </div>

          <div className="mt-12 grid gap-10 lg:grid-cols-[2fr_1fr]">
            <div>
              <p id="footer-heading" className="text-lg font-semibold">
                Sign up for our newsletter - enter your email below
              </p>
              <form
                className="mt-4 flex flex-col gap-4 sm:flex-row"
                onSubmit={(event) => event.preventDefault()}
              >
                <label htmlFor="newsletter-email" className="sr-only">
                  Email address
                </label>
                <input
                  id="newsletter-email"
                  type="email"
                  placeholder="Enter your email"
                  className="flex-1 rounded-full border border-white/20 bg-transparent px-5 py-3 text-sm text-white placeholder:text-white/50 focus:border-white focus:outline-none"
                  required
                />
                <button
                  type="submit"
                  className="inline-flex items-center justify-center rounded-full bg-white px-6 py-3 text-sm font-semibold uppercase tracking-[0.3em] text-black transition hover:bg-slate-100"
                >
                  <span aria-hidden="true">→</span>
                  <span className="sr-only">Submit email</span>
                </button>
              </form>
              <p className="mt-4 text-xs text-white/60">
                By entering your email address, you agree to our{" "}
                <a href="#" className="underline underline-offset-4">
                  Privacy Policy
                </a>
                , and will receive Aurea offers, promotions and other commercial messages. You may unsubscribe at any
                time.
              </p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.3em] text-white/60">Follow Us</p>
              <div className="mt-4 flex flex-wrap gap-3">
                {socialLinks.map((social) => (
                  <a
                    key={social.label}
                    href={social.href}
                    aria-label={social.label}
                    className="flex h-12 w-12 items-center justify-center rounded-full border border-white/30 text-sm font-semibold transition hover:border-white hover:text-white"
                  >
                    {social.shorthand}
                  </a>
                ))}
              </div>
            </div>
          </div>

          <div className="mt-12 border-t border-white/10 pt-8">
            <p className="text-xs text-white/60">
              For applicable countries, duties &amp; taxes will be automatically calculated and displayed during checkout.
              Depending on the country, you will have the option to choose Delivery Duty Paid (DDP) or Delivery Duty Unpaid
              (DDU).
            </p>
            <div className="mt-6 flex flex-wrap items-center gap-x-6 gap-y-3 text-xs text-white/60">
              <p>© 2025 Aurea. All Rights Reserved.</p>
              {legalLinks.map((legal) => (
                <a
                  key={legal}
                  href="#"
                  className="uppercase tracking-[0.25em] transition hover:text-white"
                >
                  {legal}
                </a>
              ))}
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}



