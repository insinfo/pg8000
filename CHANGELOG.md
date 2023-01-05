## 1.0.0

- Initial version

## 1.0.1

- fix bug on insert with prepared statement and implement queryUnnamed method for execute a prepared unnamed statement

## 2.0.0

- migrated to null safety 

## 2.1.0

- placeholder identifier option implemented in queryUnnamed and prepareStatement methods, 
this makes it possible to use the style similar to PHP PDO in prepared 
queries Example: 
    ``` queryUnnamed('SELECT * FROM book WHERE title = ? AND code = ?',['title',10],placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark) ```


## 2.2.0

- implemented ResultStream and Results class for return data from queryUnnamed and querySimple

## 2.2.1

- fix bug on queryUnnamed and prepareStatement