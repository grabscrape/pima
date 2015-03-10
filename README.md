# Scrape(grab) data from Pima AZ assessor.

script should take from command line following arguments:

version - default value = 1

before scrape starting script has to check if all necessary tables are exist
(<table>_<version>) and to create them if they are absent.

1. to go to
http://www.asr.pima.gov/links/frm_AdvancedSearch_v2.aspx?search=Parcel
2. To collect all street names (without direction) - can be stored in table
in order to use less memory
3. To perform search by each street name
4. To open details page for each parcel from search result page

To scrape all data from parcel page to assessor_scrape_<version> with "Book-Map-Parcel" as primary key

Valuation Data - assessor_scrape_valuation_<version>
Recording Information - assessor_scrape_recording_<version>
Owner's Estimate  - assessor_scrape_estimate_<version> with "Book-Map-Parcel" as a key.

Parcels usually have same set of fields on the page but some of them can differ.
Scrape should create additional fields in assessor_scrape_<version> automatically.

Note. Its old project. Orign site structure might by changed.
