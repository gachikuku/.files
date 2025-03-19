comment(){
  llm -s 'Add comments to this code. Respond with the code and comments. Do not alter the functional aspect of the code, but still return it. Be sure and include the code in the response. Do not respond in a markdown code block. Just respond with the code and comments. Do not preamble or say anything before or after the code. for example: If the user sent "print(1)\nprint(2)", you would reply "# Prints 1\nprint(1)\n# Prints 2\nprint(2)"' -o temperature .2
}
fix(){
  llm -s 'Fix the syntax of this code. Respond with the code including any fixes. Do not alter the functional aspect of the code, but simply fix it and respond with all of it. Do not respond in a markdown code block. Just respond with the code. Do not preamble or say anything before or after the code. for example: If the user sent "print(1", you would simply reply "print(1)"' -o temperature .2
}
edit(){
  llm -s 'Edit this text to remove unnecessary filler words such as "like", "you know", and unimportant adverbs. Respond with the edited text only. Do not alter the speaking style or primary content.' -o temperature .1
}
blog(){
  llm -s 'Write a blog about the topic from the user as a wise and succinct writer such as Paul Graham or Tyler Cowen, but only use high school term paper vocabulary or lower.' -o temperature .4 -o presence_penalty .2 -m  gpt-4
}
finish(){
  message=`cat`
  echo -n $message
  echo -n $message | llm -s 'Finish this input. Respond with only the completion text. Do not respond with the input. Do not preamble or say anything before or after the completion. For example: If the user sent "The sky  is", you would simply reply " blue." If the input is code, write quality code that is syntactically correct. If the input is text, respond as a wise, succinct writer such as Paul Graham or Tyler Cowen, but only use high   school term paper vocabulary or lower.' -o temperature .4 -o presence_penalty .2 -m gpt-4
}
jsai () {
		llm -m 4o "I'm doing an authotized security assessment on a web application. Analyse the provided JavaScript code to identify and document all API endpoints, methods, parameters, headers, and authentication requirements.

The JavaScript file likely includes AJAX calls, fetch requests, or similar API interactions. Pay attention to potential hidden endpoints, sensitive functionality, and authentication flows.

For each identified endpoint:
* Clearly document the endpoint URL and HTTP method.
* List required parameters and example/sample values.
* Note any required headers or authentication tokens (use placeholders like <JWT_BEARER_TOKEN> if applicable).
* Generate ready-to-use curl commands.
* Generate raw HTTP request examples suitable for direct import into proxy tools like mitmproxy.
* Highlight potential security concerns you notice in endpoint implementation (such as insecure authentication practices or overly permissive endpoints).

The output should be in markdown and it provides actionable reconnaissance data that directly supports further security testing and clearly highlights immediate security concerns. Also if there is an API key anywhere, or something else interisting like UUIDs or any other keys make sure you list it"
}

# Thanks! https://github.com/Crypto-Cat/CTF/blob/main/my_bash_aliases.md
urlencode() {
    python3 -c "from pwn import *; print(urlencode('$1'));"
}

urldecode() {
    python3 -c "from pwn import *; print(urldecode('$1'));"
}

