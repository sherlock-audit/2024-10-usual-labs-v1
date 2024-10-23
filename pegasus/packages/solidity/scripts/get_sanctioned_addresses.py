#!/usr/bin/env python3

import xml.etree.ElementTree as ET
import argparse
import pathlib
import json
import requests
import os

FEATURE_TYPE_TEXT = "Digital Currency Address - "
NAMESPACE = {'sdn': 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/ADVANCED_XML'}

POSSIBLE_ASSETS = ["XBT", 'ETH', "XMR", "LTC", "ZEC", "DASH", "BTG", "ETC",
                   "BSV", "BCH", "XVG", "USDT", "XRP", "ARB", "BSC", "USDC",
                   "TRX"]

OUTPUT_FORMATS = ["TXT", "JSON"]

SDN_URL = "https://www.treasury.gov/ofac/downloads/sanctions/1.0/sdn_advanced.xml"

def download_sdn_file(filepath):
    response = requests.get(SDN_URL)
    response.raise_for_status()
    with open(filepath, 'wb') as file:
        file.write(response.content)

def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Tool to extract sanctioned digital currency addresses from the OFAC special designated nationals XML file (sdn_advanced.xml)')
    parser.add_argument('assets', choices=POSSIBLE_ASSETS, nargs='*',
                        default=[POSSIBLE_ASSETS[1]], help='the asset for which the sanctioned addresses should be extracted (default: ETH (Ethereum))')
    parser.add_argument('-f', '--output-format',  dest='format', nargs='*', choices=OUTPUT_FORMATS,
                        default=[OUTPUT_FORMATS[1]], help='the output file format of the address list (default: JSON)')
    parser.add_argument('-path', '--output-path', dest='outpath',  type=pathlib.Path, default=pathlib.Path(
        "./"), help='the path where the lists should be written to (default: current working directory ("./")')
    parser.add_argument('-c', '--compare-file', dest='compare_file', type=pathlib.Path,
                        help='the path to the JSON file to compare the results with')
    return parser.parse_args()

def feature_type_text(asset):
    return "Digital Currency Address - " + asset

def get_address_id(root, asset):
    feature_type = root.find(
        "sdn:ReferenceValueSets/sdn:FeatureTypeValues/*[.='{}']".format(feature_type_text(asset)), NAMESPACE)
    if feature_type is None:
        raise LookupError(f"No FeatureType with the name {feature_type_text(asset)} found")
    address_id = feature_type.attrib["ID"]
    return address_id

def get_sanctioned_addresses(root, address_id):
    addresses = list()
    for feature in root.findall("sdn:DistinctParties//*[@FeatureTypeID='{}']".format(address_id), NAMESPACE):
        for version_detail in feature.findall(".//sdn:VersionDetail", NAMESPACE):
            addresses.append(version_detail.text.lower())
    return addresses

def write_addresses(addresses, asset, output_formats, outpath):
    if "TXT" in output_formats:
        write_addresses_txt(addresses, asset, outpath)
    if "JSON" in output_formats:
        write_addresses_json(addresses, asset, outpath)

def write_addresses_txt(addresses, asset, outpath):
    with open(f"{outpath}/sanctioned_addresses_{asset}.txt", 'w') as out:
        for address in addresses:
            out.write(address + "\n")

def write_addresses_json(addresses, asset, outpath):
    with open(f"{outpath}/sanctioned_addresses_{asset}.json", 'w') as out:
        json.dump(addresses, out, indent=2)

def load_json(filepath):
    with open(filepath, 'r') as file:
        return json.load(file)

def compare_addresses(downloaded_addresses, existing_addresses):
    new_addresses = []
    for address in downloaded_addresses:
        if address not in [addr.lower() for addr in existing_addresses]:
            new_addresses.append(address)
    return new_addresses

def main():
    args = parse_arguments()

    sdn_file_path = './sdn_advanced.xml'
    download_sdn_file(sdn_file_path)

    tree = ET.parse(sdn_file_path)
    root = tree.getroot()

    assets = args.assets

    output_formats = args.format

    for asset in assets:
        address_id = get_address_id(root, asset)
        addresses = get_sanctioned_addresses(root, address_id)

        addresses = list(dict.fromkeys(addresses).keys())
        addresses.sort()

        write_addresses(addresses, asset, output_formats, args.outpath)

        if args.compare_file:
            downloaded_addresses = addresses
            existing_addresses = load_json(args.compare_file)
            
            new_addresses = compare_addresses(downloaded_addresses, existing_addresses)
            for address in new_addresses:
                print(address)

    os.remove(sdn_file_path)
    os.remove(f"{args.outpath}/sanctioned_addresses_{asset}.json")

if __name__ == "__main__":
    main()
