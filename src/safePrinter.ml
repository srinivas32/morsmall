(******************************************************************************)
(*                                                                            *)
(*                                  Morsmall                                  *)
(*                       A concise AST for POSIX shell                        *)
(*                                                                            *)
(*   Copyright (C) 2017  Yann Régis-Gianas, Ralf Treinen, Nicolas Jeannerod   *)
(*                                                                            *)
(*   This program is free software: you can redistribute it and/or modify     *)
(*   it under the terms of the GNU General Public License as published by     *)
(*   the Free Software Foundation, either version 3 of the License, or        *)
(*   (at your option) any later version.                                      *)
(*                                                                            *)
(*   This program is distributed in the hope that it will be useful,          *)
(*   but WITHOUT ANY WARRANTY; without even the implied warranty of           *)
(*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            *)
(*   GNU General Public License for more details.                             *)
(*                                                                            *)
(*   You should have received a copy of the GNU General Public License        *)
(*   along with this program.  If not, see <http://www.gnu.org/licenses/>.    *)
(*                                                                            *)
(******************************************************************************)

let fpf = Format.fprintf
open AST
open Location

(* AST.name *)

let rec pp_name ppf =
  fpf ppf "%s"

(* AST.word_component *)

and pp_word_component ppf = function (*FIXME*)
  | Literal literal ->
     fpf ppf "%s" literal
  | Variable variable ->
     fpf ppf "${%s}" variable
  | Subshell command_list ->
     fpf ppf "$(%a)" pp_command_list command_list
  | GlobAll ->
     fpf ppf "*"
  | GlobAny ->
     fpf ppf "?"
  | GlobRange _char_range ->
     assert false
  | Other (*FIXME*) -> assert false

(* AST.word *)

and pp_word ppf = function
  | [] -> assert false
  | [e] -> pp_word_component ppf e
  | h :: q -> fpf ppf "%a%a" pp_word_component h pp_word q

and pp_word' ppf word' =
  pp_word ppf word'.value

and pp_words ppf = function
  | [] -> ()
  | [word] ->
     pp_word ppf word
  | word :: words ->
     fpf ppf "%a %a"
       pp_word word
       pp_words words

and pp_words' ppf words' =
  List.map (fun word' -> word'.value) words'
  |> pp_words ppf

(* AST.pattern *)

and pp_pattern ppf = function
  | [] -> ()
  | [word] ->
     pp_word ppf word
  | word :: pattern ->
     fpf ppf "%a|%a"
       pp_word word
       pp_pattern pattern

and pp_pattern' ppf pattern' =
  pp_pattern ppf pattern'.value

(* AST.assignement *)

and pp_assignment ppf { variable ; word } =
  fpf ppf "%a=%a"
    pp_name variable
    pp_word word

and pp_assignments ppf = function
  | [] -> ()
  | [assignment] ->
     pp_assignment ppf assignment
  | assignment :: assignments ->
     fpf ppf "%a %a"
       pp_assignment assignment
       pp_assignments assignments

and pp_assignments' ppf assignments' =
  List.map (fun assignment' -> assignment'.value) assignments'
  |> pp_assignments ppf

and pp_redirection_kind ppf k =
  fpf ppf "%s"
    (match k with
     | Input -> "<" | InputDuplicate -> "<&"
     | Output -> ">" | OutputDuplicate -> ">&" | OutputAppend -> ">>"
     | InputOutput -> "<>" | OutputClobber -> ">|")

(* AST.command *)

and pp_command ppf (command : command) =
  fpf ppf "{ ";
  (
    match command with

    | Async command ->
       pp_command ppf command

    | Seq (command1, command2) ->
       fpf ppf "%a;%a"
         pp_command' command1
         pp_command' command2

    | And (command1, command2) ->
       fpf ppf "%a&&%a"
         pp_command' command1
         pp_command' command2

    | Or (command1, command2) ->
       fpf ppf "%a||%a"
         pp_command' command1
         pp_command' command2

    | Not command ->
       fpf ppf "! %a"
         pp_command' command

    | Pipe (command1, command2) ->
       fpf ppf "%a|%a"
         pp_command' command1
         pp_command' command2

    | Subshell command ->
       fpf ppf "(%a)"
         pp_command' command

    | If { test ; body ; rest = None } ->
       fpf ppf "if %a;then %a;fi"
         pp_command' test
         pp_command' body

    | If { test ; body ; rest = Some rest } ->
       fpf ppf "if %a;then %a;else %a;fi"
         pp_command' test
         pp_command' body
         pp_command' rest

    | For { variable ; words = None ; body } ->
       fpf ppf "for %a;do %a;done"
         pp_name variable
         pp_command' body

    | For { variable ; words = Some words ; body } ->
       fpf ppf "for %a in %a;do %a;done"
         pp_name variable
         pp_words words
         pp_command' body

    | Case { word ; items } ->
       fpf ppf "case %a in" pp_word word;
       List.iter
         (fun item' ->
           match item'.value with
           | { pattern ; body = None } ->
              fpf ppf " %a) ;;" pp_pattern' pattern
           | { pattern ; body = Some body' } ->
              fpf ppf " %a) %a;;" pp_pattern' pattern pp_command' body')
         items;
       fpf ppf " esac"

    | While { test ; body } ->
       fpf ppf "while %a;do %a;done"
         pp_command' test
         pp_command' body

    | Until { test ; body } ->
       fpf ppf "until %a;do %a;done"
         pp_command' test
         pp_command' body

    | Function { name ; body } ->
       fpf ppf "%a()%a"
         pp_name name
         pp_command' body

    | Simple { assignments = [] ; words = [] } ->
       failwith "SafePrinter.pp_command': ill-formed command: Simple([], [])"
    | Simple { assignments = [] ; words } ->
       fpf ppf "%a" pp_words' words
    | Simple { assignments ; words } ->
       fpf ppf "%a %a"
         pp_assignments' assignments
         pp_words' words

    | Redirection { command ; descr ; kind ; file } ->
       (* The space is required because "the [descriptor] must be delimited from any preceding text". *)
       fpf ppf "%a %d%a%a"
         pp_command' command
         descr
         pp_redirection_kind kind
         pp_word file

    | HereDocument { command ; descr ; strip ; content } ->
       (* if content.value.[String.length content.value - 1] <> '\n' then
        *   failwith "SafePrinter.pp_command': ill-formed here-document: the content must end with a newline"; *) (*FIXME*)
       let eof = "EOF" in (*FIXME*)
       fpf ppf "%a %d%s%s\n%a%s\n"
         pp_command' command
         descr
         (if strip then "<<-" else "<<")
         eof
         pp_word' content
         eof
  );
  fpf ppf "%s}" (match command with Async _ -> "&" | HereDocument _ -> "" | _ -> ";")

and pp_command' ppf (command' : command') =
  pp_command ppf command'.value

and pp_command_list ppf = function
  | [] -> ()
  | [e] ->
     pp_command ppf e
  | h :: q ->
     fpf ppf "%a@\n%a"
       pp_command h
       pp_command_list q