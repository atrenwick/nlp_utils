# a tokeniser for French and English  using re, and lxml
# input is a text string or an etree or ET element, a list of tokens is returned
# step1 = tidy for tok
import re
import os
import glob
import argparse
from lxml import etree
from multiprocessing import Pool
from multiprocessing import Value
from multiprocessing import Lock
from functools import partial
from tqdm import tqdm
from lxml.etree import Element

def run_fr_only_replacements(this_text):
    '''
    Run string replacements specific to French language text 
    Inputs:
      this_text : str : a string of French text
    Returns:
      this_text : str : a string of French text
    '''

    this_text = re.sub(r"rud' homm", r"rud'homm", this_text)
    this_text = re.sub(r"aujourd' hui", r"aujourd'hui", this_text)
    this_text = re.sub(r'(-je|-tu|-il|-elle|-on|-ça|-cela|-nous|-vous|-ils|-elles|-moi|-toi|-lui|-leur|-en|-y|-ilz)',r' \1',this_text)
    return this_text

def run_tokeniser_core(this_text, lang, hyphen_join_value):
    ''' 
    Run tokeniser core section to apply replacements pre-tokenising
    Inputs:
      this_text: str : the text string to be tokenised
      lang : str : code of the language being processed
      hyphen_join_value : 
    '''
    this_text = re.sub('\x0D|\xa0|\r|\n|\t|\\|',' ',this_text)
    this_text = re.sub('(  )+',' ',this_text)
    this_text = re.sub('  ',' ',this_text)
    this_text = re.sub(r'\.\.\.',' … ', this_text)
      
    this_text = re.sub(r'et al',r'et_al', this_text)
    this_text = re.sub(r'et\. al',r'et_al', this_text)
    this_text = re.sub(r'et\. al\.',r'et_al', this_text)
    this_text = re.sub(r'e\.g\.',r'e_g_', this_text)
    
    this_text = re.sub(r'i\.e\.',r'i_e_', this_text)
    this_text = re.sub(r'i\.e\.',r'i_e_', this_text)

    this_text = re.sub(r'i\. e \. ,',r'i_e_', this_text)
    this_text = re.sub(r'i\. e \.',r'i_e_', this_text)
    this_text = re.sub(r',\.$',r'.', this_text)
    this_text = re.sub(r',\. ',r'. ', this_text)
    this_text = re.sub(r'\.,',r'. ', this_text)
    this_text = re.sub(r'(htt(p|ps)://.+?($| ))',' _URL_ ',this_text)
    if lang in ("fr", "FR"):
      this_text = re.sub(r"[’''’]", "' ", this_text)
      this_text = run_fr_only_replacements(this_text)
    if lang == ("en", "EN"):
      this_text = re.sub(r"[’''’]", "'", this_text)
      this_text = re.sub(r"[“”]", '"', this_text)
      
    this_text = re.sub(r'([,\]\[;:\-&\(\)?!\.«»“”"])',r' \1 ',this_text)

    if hyphen_join_value != True:
      this_text = re.sub(r'(–)',r' \1 ', this_text)
      this_text = re.sub(r'(-)',r' \1 ', this_text)
    if hyphen_join_value == True:
      this_text = re.sub(r' (-) ',r'\1', this_text)  
      this_text = re.sub(r' (–) ',r'\1', this_text)
    this_text = this_text.replace('  ',' ').replace('  ',' ').replace('  ',' ').replace('  ',' ').replace('\n',' \n ')
    this_text = re.sub('(  )+',' ',this_text)
    this_text = re.sub('  ', ' ', this_text )
    this_text = re.sub('\t\t','\t',this_text)
    this_text = re.sub('(\n\n)+','\n',this_text)
    this_text = re.sub('^ | $','',this_text)
    return this_text
    
def get_text_from_input(input_text):
    '''
    Get the string of text from a string or an etree Element
    Input:
      input_text: etree Element or string : an etree Element with a string in the text attribute or a string
    Return :
      output_text : str : a text string
    '''

    # if the input is of type string, return the string unmodified
    if isinstance(input_text, str):
      output_text = input_text
    
    # if the input is not a string, iterate over the text in the element, strip and concatenate the text 
    else:
      output_text = ''.join([chunk for chunk in input_text.itertext()]).strip()
    return output_text

def get_tok_from_text(text):
    '''
    Split the tidied text into tokens based on spaces
    Inputs :
      text : string : a text string to tokenise
    Returns:
      tokens_tidy : list : a list of tokens
    '''
    # split the text into tokens on spaces and return the list of non "" elements
    tokens_raw = text.split(" ")
    tokens_tidy = [tok for tok in tokens_raw if tok != ""]
    return tokens_tidy

def run_tokenizer(input_text, lang, hyphen_join_value):
  '''
  Run the three steps of the tokenisation pipeline
  Inputs :
      input_text: etree Element or string : an etree Element with a string in the text attribute or a string
  Returns:
      tokens_tidy : list : a list of tokens
  '''

  this_text = get_text_from_input(input_text)
  this_text = run_tokeniser_core(this_text, lang, hyphen_join_value)
  tokens_tidy = get_tok_from_text(this_text)
  return tokens_tidy
  




def tokenise_file(input_file, lang, hyphen_join_value):
  '''
  Run all steps of tokenisation for a file, to pass as basis for partial function
  '''

  # use the global variables shared by the pool
  global counter, counter_lock

  with counter_lock:
      counter.value += 1
      w_count = counter.value

  # get the tree and its s elements  
  tree_in = etree.parse(input_file)
  p_els = tree_in.findall(".//p")

  # define a dictionary of custom replacements to allow proper processing of Latin abbreviations
  tok_repl_dict =   {'e_g_': 'e.g.', 'e_g_#': 'e.g.,', 'et_al': 'et al.',
 'i_e_#': 'i.e.,', 'i_e_': 'i.e.'}

  # run the tokeniser for each p element, adding a w element to each p el for each token, and when done, set p_el text to ""
  for p_el in (p_els):
    tokens_tidy = run_tokenizer(p_el, lang, hyphen_join_value)
    for tok in tokens_tidy:
      w_el = etree.SubElement(p_el, "w")
      w_count +=1
      w_el.set("id", str(w_count))
      if tok in tok_repl_dict.keys():
        tok = tok_repl_dict[tok]
      w_el.text = str(tok)

    p_el.text = ""  
  
  ## make the name for the output file, then verify that target directory exists, as well as the directory in which the target directory is located also exists
  outputfile = input_file.replace('.xml','tokenised.xml').replace('step1','step2')  
  f_plus1 = os.path.dirname(outputfile)
  f_plus2 = os.path.dirname(f_plus1)
  for this_path in [f_plus2, f_plus1]:
    if os.path.exists(this_path) is False:
      os.mkdir(this_path)
  
  tree_in.write(outputfile, encoding='UTF-8', pretty_print=True, xml_declaration=True) 


def init(shared_counter, lock):
    '''
    initialiser function to set and lock a counter to be shared between pool processors
    Inputs :
      shared_counter : counter : the counter to be shared
      lock : lock : a lock
    Returns :
      no return object 2 globals declared
    '''
    global counter, counter_lock
    counter = shared_counter
    counter_lock = lock



    
def pool_tokenise(files, n_procs, lang, hyphen_join_value):
  '''
  Tokenise files with a processor pool
  inputs:
    files : list : a list of files to tokenise
    n_procs : int : number of processors to use in the processor pool
    lang : string : language code of the texts to be tokenised
    hyphen_join_value : bool : should hyphenated tokens be joined in French
  Returns :
    no return object : a processor pool will be created, each processor tokenising and printing files
  '''
  # define worker  function to send to each processor
  worker = partial(tokenise_file, lang=lang, hyphen_join_value=hyphen_join_value)

  # initialise the shared counter and lock
  shared_counter = Value("i", 0)   # int, initialized to 0
  lock = Lock()
  
  # use the pool to process the files unordered, with a progress bar  
  with Pool(processes=n_procs, initializer=init, initargs=(shared_counter, lock)) as pool:
      for _ in tqdm(pool.imap_unordered(worker, files), total=len(files)):
          pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='''Process files with multiprocessing.
    
    Usage : 
      example : process files in /home/folder with 4 processors in pool, joining hyphens set to True for files in French
      tokeniser.py -inputPath /home/folder --nprocs 4 -join_hyphen True --lang fr
            
    ''')
    parser.add_argument(
        "-inputPath", type=str,help="path to folder containing XML"
    )
    parser.add_argument(
        "--nprocs", type=int, default=2,
        help="Number of worker processes to use"
    )
    parser.add_argument(
        "-join_hyphen", type=bool, default=True,
        help="Should hyphenated forms other than PRON be joined"
    )
    parser.add_argument(
        "--lang", type=str, default="en",
        help="Language code (e.g., en, fr, de)"
    )
    args = parser.parse_args()
    
    path = args.inputPath
    n_procs = args.nprocs
    lang = args.lang
    hyphen_join_value = args.join_hyphen
    files = glob.glob(f'{path}/*.xml')

    files = [x for x in files if "tokenised.xml" not in x]
    print(f'{len(files)} files found : processing with {n_procs} workers')

    pool_tokenise(files, n_procs, lang, hyphen_join_value)
