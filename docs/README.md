# BMSSP Benchmark Game Documentation

This directory contains the GitHub Pages site for the BMSSP Benchmark Game project.

## Site Structure

- `index.md` - Main landing page
- `algorithm.md` - Algorithm theory and mathematical analysis
- `implementations.md` - Language implementation details and comparison
- `benchmarking.md` - Benchmarking guide and performance analysis
- `getting-started.md` - Setup and first steps guide

## Build Locally

To build and serve the site locally:

```bash
cd docs
bundle install
bundle exec jekyll serve
```

Then open http://localhost:4000 in your browser.

## GitHub Pages Deployment

The site is automatically deployed to GitHub Pages via GitHub Actions when changes are pushed to the main branch. The workflow is defined in `.github/workflows/pages.yml`.

## Configuration

- `_config.yml` - Jekyll configuration and site metadata
- `_layouts/default.html` - Custom layout with navigation
- `_includes/navigation.html` - Navigation component
- `Gemfile` - Ruby gem dependencies

## Features

- Responsive design with minimal theme
- Mathematical notation support via MathJax
- Syntax highlighting for code blocks
- SEO optimization with structured metadata
- Mobile-friendly navigation