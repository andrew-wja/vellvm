; TEST-ARGS: -omit-array-size=140
@s = constant [141 x i8]  c"1111111111111111111122222222222222222222333333333333333333334444444444444444444455555555555555555555666666666666666666677777777777777777777\0"

define i8 @src() {
  %p = bitcast [141 x i8]* @s to i8*
  %one = load i8, i8* %p
  ret i8 %one
}

define i8 @tgt() {
  %p = bitcast [141 x i8]* @s to i8*
  %one = load i8, i8* %p
  ret i8 %one
}

; Assertions below this point were automatically generated

; ASSERT SRCTGT 100
